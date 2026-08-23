import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/animals.dart';
import '../models/loadable.dart';
import '../models/race_payouts.dart';
import '../models/next_race.dart';
import '../models/race_prize_pool.dart';
import '../services/activation_analytics_service.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../services/discovery_join_coordinator.dart';
import '../services/notification_service.dart';
import '../services/race_chat_service.dart';
import '../services/race_feed_service.dart';
import '../services/race_stream_coordinator.dart';
import '../services/app_route_observer.dart';
import '../styles.dart';
import '../widgets/modal_action_button.dart';
import '../widgets/app_refresh_indicator.dart';
import '../utils/at_name.dart';
import '../utils/effect_polarity.dart';
import '../utils/funded_exposure_error_copy.dart';
import '../utils/powerup_error_copy.dart';
import '../utils/race_display.dart';
import '../utils/race_participant_display.dart';
import '../utils/share_helper.dart';
import '../utils/team_race.dart';
import '../widgets/ad_banner_slot.dart';
import '../widgets/arcade_fx.dart';
import '../widgets/arcade_tab_selector.dart';
import '../widgets/app_avatar.dart';
import '../widgets/error_toast.dart';
import '../widgets/global_event_banner.dart';
import '../widgets/goal_track.dart';
import '../widgets/home_chrome.dart';
import '../widgets/home_course_track.dart';
import '../widgets/info_toast.dart';
import '../widgets/pill_button.dart';
import '../widgets/retro_card.dart';
import '../widgets/trail_sign.dart';
import '../widgets/powerup_icon.dart';
import '../widgets/pocket_watch_sheet.dart';
import '../widgets/attack_outcome_modal.dart';
import '../widgets/powerup_reveal_modal.dart';
import '../widgets/spinning_coin.dart';
import '../widgets/coin_balance_badge.dart';
import '../widgets/spinning_crate.dart';
import '../widgets/game_container.dart';
import '../widgets/friend_request_sheet.dart';
import '../widgets/leaderboard_plank.dart';
import '../services/ad_service.dart';
import '../widgets/multiplier_chip.dart';
import '../widgets/race_podium.dart';
import '../widgets/race_payout_scorecard.dart';
import '../widgets/team_lobby_board.dart';
import '../widgets/team_scoreboard_cards.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/race_ui.dart';
import '../widgets/race_alert_opt_in_card.dart';
import '../widgets/item_slot.dart';
import '../widgets/feed_bubble.dart';
import '../widgets/player_avatar.dart';
import 'case_opening_screen.dart';
import 'multi_case_opening_screen.dart';
import 'edit_race_screen.dart';
import 'tournament_detail_screen.dart';
import 'race_invite_screen.dart';
import '../constants/powerup_copy.dart';

class RaceDetailScreen extends StatefulWidget {
  final AuthService authService;
  final String raceId;
  final List<Map<String, dynamic>> friends;
  final BackendApiService backendApiService;
  final NotificationService? notificationService;
  final ActivationAnalyticsService? activationAnalyticsService;

  /// Fired once a mystery-box reveal has finished and its overlay has closed.
  /// The host uses it for the relocated notification ask (spec §5.4) — this is
  /// the first genuinely delightful moment a new user reaches, and the only one
  /// that reliably happens inside session one. Nothing else hangs off it:
  /// deliberately NO just-in-time tip fires here, because two interruptions on
  /// one trigger would be worse than the problem being solved.
  final Future<void> Function()? onBoxOpened;

  /// Only set when this screen is rendered behind the onboarding tutorial's
  /// spotlight; anchors the "Powerups & boxes" callout to the inventory block.
  /// Null in the real app.
  final GlobalKey? tutorialPowerupsKey;

  /// Only set by the onboarding demo race; anchors beat 8's mark to the hero
  /// countdown chip. Null in the real app, exactly like [tutorialPowerupsKey].
  final GlobalKey? tutorialClockKey;

  /// Demo-race tap gate. Given a tray item, returns false to SWALLOW the tap.
  ///
  /// Null in the real app, where every tap is always allowed — this must never
  /// gate a real race. The demo uses it to stop an off-script tap before it
  /// navigates (the box reel is pushed *before* its API call, so there is no
  /// later point at which a refusal is still invisible) and to nudge the coach
  /// toward the control the current beat is actually asking for.
  final bool Function(Map<String, dynamic> item)? demoTapGate;

  /// Onboarding-demo target gate. Returns false to REFUSE a tap on a row of
  /// the target picker, leaving the sheet open. The demo's script names the
  /// rival to hit ("pick CapyBot"), and without this the user could hit anyone —
  /// an instruction the app does not enforce reads as a suggestion. Null (the
  /// shipped app) allows every target.
  final bool Function(String userId)? demoTargetGate;

  /// Renders this screen as the onboarding **demo race** (spec §5.7).
  ///
  /// Suppression only: it hides ads, the notification opt-in card, the starter
  /// reward, share/invite/options, and the destructive or off-script powerup
  /// actions (discard, upgrade ladders, OPEN ALL). It deliberately does **not**
  /// change how standings, powerups, boxes, the course or the target picker
  /// render — if it did, the demo would stop being the real screen and the
  /// whole premise collapses.
  final bool demoMode;

  /// Item 11 — injectable rewarded-ad controller for the box reroll, so widget
  /// tests never touch google_mobile_ads. Null in production, where the screen
  /// builds a real [AdService] on its own dedicated ad unit.
  final ExtraSpinAdController? boxRerollAdController;
  final bool showPostCreateSharePrompt;

  RaceDetailScreen({
    super.key,
    required this.authService,
    required this.raceId,
    this.friends = const [],
    BackendApiService? backendApiService,
    this.notificationService,
    this.activationAnalyticsService,
    this.onBoxOpened,
    this.tutorialPowerupsKey,
    this.tutorialClockKey,
    this.demoTapGate,
    this.demoTargetGate,
    this.demoMode = false,
    this.boxRerollAdController,
    this.showPostCreateSharePrompt = false,
  }) : backendApiService = backendApiService ?? BackendApiService();

  @override
  State<RaceDetailScreen> createState() => _RaceDetailScreenState();
}

// Short-form descriptions used in the active-effects list, where the
// countdown badge on the right already conveys the remaining duration.

const _rarityColors = {
  'COMMON': Color(0xFF8B8B8B),
  'UNCOMMON': Color(0xFF4A90D9),
  'RARE': Color(0xFFD4A017),
};

// Retired powerups stay readable in historical Activity but never render as a
// usable inventory or stash action in this build.
const _hiddenPowerupTypes = {'IMPOSTER'};

/// Converts the versioned `powerupData.inventory` payload into a safe local
/// projection. Older backends can omit it, and malformed entries must never
/// prevent the race detail from rendering.
List<Map<String, dynamic>> normalizePowerupInventory(Object? rawInventory) {
  if (rawInventory is! List) return const [];

  return [
    for (final rawEntry in rawInventory)
      if (rawEntry is Map &&
          rawEntry['type'] != 'IMPOSTER' &&
          rawEntry['powerupType'] != 'IMPOSTER')
        <String, dynamic>{
          for (final MapEntry(:key, :value) in rawEntry.entries)
            if (key is String) key: value,
        },
  ];
}

bool _isUnopenedMysteryBoxSlot(Map<String, dynamic> powerup) {
  final id = powerup['id'];
  return powerup['status'] == 'MYSTERY_BOX' &&
      id is String &&
      id.trim().isNotEmpty;
}

// Powerup upgrade price tables — FALLBACK ONLY. The backend is authoritative:
// getRaceProgress powerupData.upgradeCosts carries the live ladders and wins
// when present (see _upgradeCostFor). These bundled copies are used only
// against an older backend that doesn't send them yet.
const _upgradeCosts = {
  'COMMON': [0, 5, 15, 45],
  'UNCOMMON': [0, 10, 30, 90],
  'RARE': [0, 15, 45, 135],
};

// Per-type overrides of the rarity ladder. Currently empty (Lucky Horseshoe's
// premium ladder was retired — it now prices as plain RARE).
const _upgradeCostsByType = <String, List<int>>{};

// Per-tier effect labels for the use-modal. Index 0 = base.

bool _isUpgradeable(String? type) => PowerupCopy.isUpgradeable(type);

class _ActiveImpactNotice {
  const _ActiveImpactNotice({
    required this.id,
    required this.powerupType,
    required this.deltaSteps,
    required this.resolvedAt,
    this.description,
  });

  final String id;
  final String powerupType;
  final int deltaSteps;
  final DateTime resolvedAt;
  final String? description;

  static _ActiveImpactNotice? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final powerupType = raw['powerupType'];
    final delta = raw['deltaSteps'];
    final valueStatus = raw['valueStatus'];
    final resolvedAt = raw['resolvedAt'];
    final rawDescription = raw['description'];
    if (id is! String ||
        id.isEmpty ||
        powerupType is! String ||
        powerupType.isEmpty ||
        delta is! num ||
        !delta.isFinite ||
        delta != delta.roundToDouble() ||
        delta == 0 ||
        valueStatus != 'SYNCED_SNAPSHOT' ||
        resolvedAt is! String) {
      return null;
    }
    final parsedResolvedAt = DateTime.tryParse(resolvedAt);
    if (parsedResolvedAt == null) return null;
    return _ActiveImpactNotice(
      id: id,
      powerupType: powerupType,
      deltaSteps: delta.toInt(),
      resolvedAt: parsedResolvedAt,
      description: rawDescription is String && rawDescription.trim().isNotEmpty
          ? rawDescription
          : null,
    );
  }
}

bool _isPopupEligibleImpact(_ActiveImpactNotice notice) {
  if (notice.deltaSteps == 0) return false;
  switch (notice.powerupType.toUpperCase()) {
    case 'PROTEIN_SHAKE':
      return false;
    case 'SHORTCUT':
      // The caster's positive side is intentionally silent; only the victim
      // sees the popup for an incoming Shortcut.
      return notice.deltaSteps < 0;
    case 'LEG_CRAMP':
    case 'WRONG_TURN':
    case 'DETOUR_SIGN':
    case 'RED_CARD':
    case 'PINECONE_TOSS':
    case 'SNEAKY_SWAP':
    case 'SIGNAL_JAMMER':
    case 'HITCHHIKE':
    case 'DRILL_SERGEANT':
    case 'LEECH':
    case 'RUNNERS_HIGH':
    case 'GHOST_PEPPER':
      return true;
    default:
      return false;
  }
}

class _ActiveImpactReceipt {
  const _ActiveImpactReceipt({required this.id, required this.raceId});

  final String id;
  final String raceId;

  static _ActiveImpactReceipt? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final raceId = raw['raceId'];
    if (id is! String || id.isEmpty || raceId is! String || raceId.isEmpty) {
      return null;
    }
    return _ActiveImpactReceipt(id: id, raceId: raceId);
  }
}

// Defensively parse a {KEY: [int, int, int, int]} cost table from the backend.
// Returns null when absent/malformed so callers can fall back to the bundled
// tables (older backends don't send upgradeCosts at all).
Map<String, List<int>>? _parseCostTable(dynamic raw) {
  if (raw is! Map) return null;
  final out = <String, List<int>>{};
  raw.forEach((key, value) {
    if (key is String && value is List) {
      final tiers = value
          .map((e) => e is num ? e.toInt() : null)
          .whereType<int>()
          .toList();
      if (tiers.length >= 4) out[key] = tiers;
    }
  });
  return out;
}

/// What the race-detail screen should do to its progress poll in response to an
/// app-lifecycle change. Kept as a pure function (no State, no timers) so the
/// pause/resume decision is unit-testable without standing up the whole screen
/// and its API harness.
enum RacePollLifecycleAction {
  /// Do nothing to the poll: a transient state (inactive/detached), or a resume
  /// for a screen that was never polling (e.g. a finished or scheduled race).
  none,

  /// Went off-screen (backgrounded/hidden): cancel the poll timer.
  pause,

  /// Came back to the foreground after having polled: refresh once immediately,
  /// then restart the periodic poll.
  resume,
}

/// Decides the poll action for [state] given whether the screen was actively
/// polling ([wasPolling]). `paused`/`hidden` pause; a `resumed` only resumes
/// when we were polling before (so we never start polling on a screen that
/// never did — e.g. a finished race); everything else is a no-op.
RacePollLifecycleAction racePollLifecycleAction(
  AppLifecycleState state, {
  required bool wasPolling,
}) {
  switch (state) {
    case AppLifecycleState.paused:
    case AppLifecycleState.hidden:
      return RacePollLifecycleAction.pause;
    case AppLifecycleState.resumed:
      return wasPolling
          ? RacePollLifecycleAction.resume
          : RacePollLifecycleAction.none;
    case AppLifecycleState.inactive:
    case AppLifecycleState.detached:
      return RacePollLifecycleAction.none;
  }
}

class _RaceDetailScreenState extends State<RaceDetailScreen>
    with WidgetsBindingObserver, RouteAware {
  Map<String, dynamic>? _race;
  Map<String, dynamic>? _progress;
  Map<String, dynamic>? _powerupData;

  /// Raw `powerupData.dropOdds` (spec §5.3), passed to the box-opening reel
  /// untouched — parsing/validation lives in [OddsBreakdown] so a malformed
  /// payload hides the affordance instead of rendering wrong odds.
  Map<String, dynamic>? get _serverDropOdds {
    final raw = _powerupData?['dropOdds'];
    return raw is Map<String, dynamic> ? raw : null;
  }

  /// Server-authoritative powerup rarity table. Absent on older backends, in
  /// which case the reel keeps using its bundled fallback map.
  Map<String, String>? get _serverRarityByType {
    final raw = _powerupData?['rarityByType'];
    if (raw is! Map) return null;
    final out = <String, String>{};
    raw.forEach((key, value) {
      if (key is String && value is String && value.isNotEmpty) {
        out[key] = value.toUpperCase();
      }
    });
    return out.isEmpty ? null : out;
  }

  // Active global step-multiplier event (BeReal-style 2x window), if any. Read
  // defensively from getRaceProgress: an older backend omits this field, which
  // simply means no banner. { active: true, multiplier, endsAt }.
  Map<String, dynamic>? _globalEvent;
  Loadable<Map<String, dynamic>> _progressState = const Loadable.initial();
  int _impactAttemptGeneration = 0;
  Future<void> _raceOverlayTail = Future<void>.value();
  int _raceOverlayPending = 0;
  bool _backgroundedSinceLastResume = false;
  int _queuedBoxCount = 0;
  // Globally-owned (coin-purchased) powerups, by type -> quantity. Spendable
  // into this race via the redeem flow. Loaded best-effort; an older backend
  // without the endpoint leaves this empty (no extra UI, no crash).
  Map<String, int> _globalPowerupInventory = const {};
  bool _isLoading = true;
  bool _isActing = false;
  bool? _acceptingInvite;
  // Set only by the missing-token early return in _loadDetails, so the
  // failed-load panel can tell "you're signed out" (no retry can fix that)
  // apart from a real network/server failure (retry might).
  bool _authMissing = false;
  // The last details-load failure message, shown on the failed-load panel
  // instead of a generic "pull to retry" so the user knows what happened —
  // mirrors tournament_detail_screen's equivalent panel.
  String? _detailsError;
  // Shared by the pull-to-refresh gesture and the panel's TRY AGAIN button so
  // a user mashing both doesn't fire concurrent detail fetches.
  Future<void>? _detailsInFlight;
  late bool _postCreateSharePromptVisible;

  /// WHICH action is in flight (batch 2026-08-08, item 12).
  ///
  /// [_isActing] stays as the global "one action at a time" guard; this id only
  /// decides which single button shows a spinner, so tapping USE on one stash
  /// row no longer greys out every button on the screen with no explanation.
  ///
  /// Ids: a HELD powerup's `id`, or `stash:<TYPE>` for a global-stash row, or
  /// [_openAllActionId] for the batch open.
  ///
  /// MUST be cleared in a `finally`: the demo's `DemoRaceApiService` resolves
  /// synchronously, and a spinner that outlives the response freezes a
  /// tutorial button mid-script (ui-test-planner risk 6).
  String? _actingPowerupId;

  static const String _openAllActionId = '__open_all__';

  /// Sets/clears the per-action busy id alongside the global guard.
  void _beginAction(String? actionId) {
    if (!mounted) return;
    setState(() {
      _isActing = true;
      _actingPowerupId = actionId;
    });
  }

  void _endAction() {
    if (!mounted) return;
    setState(() {
      _isActing = false;
      _actingPowerupId = null;
    });
  }

  // The viewer is not (or is no longer) a participant: `GET /races/:id/details`
  // answered 403. Reached two ways — opening a stale link, or being pruned from
  // a seeded challenge while the screen is open. Terminal for this screen: once
  // set, every poller is stopped and the board is replaced by one honest state
  // rather than a repeating error toast over stale data.
  bool _notAParticipant = false;
  Timer? _pollTimer;
  Timer? _countdownTimer;
  // Whether this screen wants to be polling progress (true only for an ACTIVE
  // race). Drives lifecycle resume: we restart the poll on foreground only when
  // it was running, never on a screen that never polled (finished/pending).
  // Stays true across a pause so resume knows to restart; cleared when polling
  // stops for good (race COMPLETED).
  bool _pollingActive = false;
  // Whether the 1s countdown ticker should be running (ACTIVE races and PENDING
  // scheduled races). Same lifecycle contract as _pollingActive.
  bool _countdownActive = false;
  // Monotonic id of the newest fetchRaceProgress request — see _loadProgress.
  int _progressFetchSeq = 0;

  /// Rank of the first racer on the page currently displayed, zero-based.
  ///
  /// The board shows exactly ONE page at a time and NEXT/PREV move this
  /// window — it does not accumulate. An append model made the control lie
  /// about itself ("SHOW 376 MORE" appending 25) and grew the page without
  /// bound; a window has a fixed height and an honest position readout.
  int _participantsOffset = 0;

  /// Racers per page. The server clamps a page to 50.
  static const int _kParticipantsPageSize = 15;
  int? _participantsTotal;
  bool _participantsHasMore = false;
  bool _participantsLoadingMore = false;
  late DateTime _countdownNow;
  bool _routeVisible = true;
  bool _appResumed = true;
  bool _returnRefreshRunning = false;
  bool _returnRefreshImpactRequested = false;
  bool _initialDetailsLoadCompleted = false;
  ModalRoute<dynamic>? _subscribedRoute;

  // Activity/Chat tabs state.
  // 0 = Activity (system/powerup events, default), 1 = Chat (user messages).
  int _activityTabIndex = 0;

  // Chat tab (user messages).
  RaceChatService? _chat;
  bool _chatHasUnread = false;
  final TextEditingController _messageInput = TextEditingController();
  final FocusNode _messageFocus = FocusNode();
  bool _sendingMessage = false;
  bool _sharingRace = false;
  // Anchors the iOS/iPad share popover to the share button's rect.
  final GlobalKey _shareButtonKey = GlobalKey();

  // Per-race notification opt-out. One toggle that silences BOTH live
  // placement-change pushes and chat-message pushes for this race. Seeded from
  // the race payload (`myPlacementAlertsMuted`/`myChatMuted`) and toggled
  // optimistically, flipping both backend flags together.
  bool _placementMuted = false;
  bool _togglingPlacementMute = false;
  bool _alertPermissionUndetermined = false;
  Map<String, dynamic>? _starterReward;
  bool _starterRewardModalShown = false;

  // Activity tab (system/powerup events).
  RaceFeedService? _feed;

  /// In flight for the spectator banner's JOIN CTA (preview mode).
  bool _joiningFromPreview = false;
  bool _feedInitialized = false;
  bool _chatInitialized = false;
  RaceStreamCoordinator? _streams;

  /// Whether the user opened up the full standings board. Held on the State so
  /// the 5s progress poll can't collapse a board the user deliberately opened.
  bool _standingsExpanded = false;
  final GlobalKey _standingsVisibilityKey = GlobalKey();
  final GlobalKey _leaderboardViewportKey = GlobalKey();
  bool _leaderboardWasVisible = false;
  bool _leaderboardVisibilityCheckScheduled = false;

  String get _myUserId => widget.authService.userId ?? '';
  BackendApiService get _api => widget.backendApiService;

  /// Serializes the screen's full-screen presentation routes. Starter reward,
  /// inline powerup outcomes, and active impact notices all use this lane so a
  /// resume or slow notice response can never stack one dialog over another.
  Future<void> _runRaceOverlay(Future<void> Function() show) {
    _raceOverlayPending += 1;
    final next = _raceOverlayTail.catchError((_) {}).then((_) async {
      try {
        if (!mounted) return;
        await show();
        // `showDialog` completes when pop begins, before its reverse transition
        // has left the overlay. Keep the lane occupied through that transition
        // so the next queued reveal never shares a frame with the prior route.
        await Future<void>.delayed(const Duration(milliseconds: 250));
      } finally {
        _raceOverlayPending -= 1;
      }
    });
    _raceOverlayTail = next;
    return next;
  }

  bool _canPresentActiveImpact({required int attempt}) {
    if (!mounted ||
        widget.demoMode ||
        attempt != _impactAttemptGeneration ||
        !_appResumed ||
        !_routeVisible ||
        _notAParticipant ||
        _race?['status'] != 'ACTIVE' ||
        _progress?['status'] != 'ACTIVE' ||
        _race?['myStatus'] != 'ACCEPTED') {
      return false;
    }
    final route = ModalRoute.of(context);
    return route == null || route.isCurrent;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null && !identical(route, _subscribedRoute)) {
      if (_subscribedRoute != null) appRouteObserver.unsubscribe(this);
      _subscribedRoute = route;
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPushNext() {
    _routeVisible = false;
    _leaderboardWasVisible = false;
    _pauseCoveredTimers();
  }

  @override
  void didPopNext() {
    _routeVisible = true;
    _scheduleLeaderboardVisibilityCheck();
    // Route uncover (case opening, picker, or another child page) refreshes
    // progress but is not a foreground-resume notification opportunity.
    unawaited(_refreshAfterCoverage(deliverImpactNotices: false));
  }

  void _pauseCoveredTimers() {
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    _streams?.pause();
  }

  Future<void> _refreshAfterCoverage({
    required bool deliverImpactNotices,
  }) async {
    // Coalesce a genuine foreground request into a route-uncover refresh that
    // may already be waiting on progress. Dropping it would postpone a notice
    // until the next background/resume cycle.
    if (deliverImpactNotices) _returnRefreshImpactRequested = true;
    if (!_routeVisible || !_appResumed) return;
    if (_returnRefreshRunning) return;
    _returnRefreshRunning = true;
    try {
      do {
        if (_pollingActive) await _loadProgress();
        if (!_routeVisible || !_appResumed) return;
        if (_returnRefreshImpactRequested) {
          _returnRefreshImpactRequested = false;
          await _attemptActiveImpactDelivery();
        }
        if (!_routeVisible || !_appResumed) return;
        // A preview viewer has no access to the feed/chat endpoints (they still
        // 403 for non-participants), so returning to the screen must not open
        // them either.
        if (!_feedInitialized && !_isPreviewViewer) {
          _ensureFeedInitialized(poll: _pollingActive);
        } else if (_feedInitialized) {
          await _streams?.resume(chatVisible: _activityTabIndex == 1);
        }
        if (!_routeVisible || !_appResumed) return;
        if (_pollingActive) _startPolling();
        if (_countdownActive) _startCountdown();
      } while (_returnRefreshImpactRequested);
    } finally {
      _returnRefreshRunning = false;
    }
  }

  int _readInt(dynamic value, {required int fallback}) {
    if (value is num) return value.toInt();
    if (value is String) {
      return int.tryParse(value) ?? double.tryParse(value)?.toInt() ?? fallback;
    }
    return fallback;
  }

  int? _readNullableInt(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    if (value is String) {
      return int.tryParse(value) ?? double.tryParse(value)?.toInt();
    }
    return null;
  }

  String _formatCoinAmount(dynamic value) {
    return (_readNullableInt(value) ?? value ?? 0).toString();
  }

  // -- Server-paginated participants ----------------------------------------
  //
  // `_race['participants']` is a PAGE, not the field, once this build's
  // `race_participants_paging` capability token meets a backend that honours
  // it. The load-bearing consequence is that THE VIEWER'S OWN ROW IS NOT
  // GUARANTEED TO BE IN IT — so no count, membership test, team assignment or
  // "my steps" read may scan the array. Each accessor below reads the additive
  // top-level summary field and returns null when it is absent (an older
  // backend, or a response served whole); every caller then falls back to the
  // pre-pagination array scan, which is exactly today's behaviour.

  /// The race's true ACCEPTED field size, or null when the backend didn't say.
  int? get _summaryAcceptedCount {
    final value = _readNullableInt(_race?['acceptedCount']);
    return (value == null || value < 0) ? null : value;
  }

  /// Per-side ACCEPTED counts for a team race; null on non-team races and on
  /// any backend that doesn't send them.
  int? get _summaryTeamAAcceptedCount {
    final value = _readNullableInt(_race?['teamAAcceptedCount']);
    return (value == null || value < 0) ? null : value;
  }

  int? get _summaryTeamBAcceptedCount {
    final value = _readNullableInt(_race?['teamBAcceptedCount']);
    return (value == null || value < 0) ? null : value;
  }

  /// The viewer's own step total in this race, served top-level precisely
  /// because their participant row may be off-page. Null => unavailable.
  int? get _summaryMyTotalSteps {
    final value = _readNullableInt(_race?['myTotalSteps']);
    return (value == null || value < 0) ? null : value;
  }

  /// Every user id in the race (bare strings, not profiles) — sent only when
  /// the array is actually truncated. Null when absent/malformed, in which
  /// case `participants` itself is the full roster.
  List<String>? get _summaryParticipantUserIds {
    final raw = _race?['participantUserIds'];
    if (raw is! List) return null;
    return raw.whereType<String>().toList(growable: false);
  }

  /// True when the server honoured our paging capability token for this
  /// response — NOT "the array is truncated". The backend sends
  /// `participantsPagination` whenever the token was honoured, including the
  /// "I returned everyone anyway" case, so this only means the response's
  /// `my*`/summary fields are the paging-safe ones, not that rows are
  /// missing. Read defensively: the key is only ever present when the
  /// capability token was honoured.
  bool get _serverHonouredParticipantsPaging =>
      _race?['participantsPagination'] is Map;

  /// The viewer's own participant status, from the top-level field the backend
  /// derives via a dedicated `(raceId, userId)` lookup — never from the page.
  String? get _myParticipantStatus {
    final value = _race?['myStatus'];
    return value is String && value.isNotEmpty ? value : null;
  }

  static const _scheduledMonthAbbrev = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  // 1.1.7: render a scheduled auto-start time in the viewer's local timezone.
  String _formatScheduledStart(DateTime t) {
    final local = t.toLocal();
    final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final m = local.minute.toString().padLeft(2, '0');
    final ampm = local.hour < 12 ? 'AM' : 'PM';
    return '${_scheduledMonthAbbrev[local.month - 1]} ${local.day} · $h:$m $ampm';
  }

  @override
  void initState() {
    super.initState();
    _postCreateSharePromptVisible = widget.showPostCreateSharePrompt;
    if (_postCreateSharePromptVisible && !widget.demoMode) {
      unawaited(
        _activationAnalytics.record(
          'race_share_prompt_shown',
          context: {'race_id': widget.raceId},
        ),
      );
    }
    WidgetsBinding.instance.addObserver(this);
    _countdownNow = DateTime.now();
    _messageFocus.addListener(_onComposerFocusChanged);
    _loadDetails();
    // §5.6/G3: the demo must never claim the starter reward (a second, real
    // 100-coin grant) nor read the OS notification permission state — reading
    // it is what arms the opt-in card whose tap fires the real prompt.
    if (!widget.demoMode && widget.authService.onboardingV2Enabled) {
      _loadStarterReward();
      _loadAlertPermissionState();
    }
  }

  late final ActivationAnalyticsService _activationAnalytics =
      widget.activationAnalyticsService ??
      ActivationAnalyticsService(backendApiService: _api);

  Future<void> _loadAlertPermissionState() async {
    final service = widget.notificationService;
    if (service == null) return;
    final state = await service.getPermissionState();
    if (mounted) setState(() => _alertPermissionUndetermined = state == null);
  }

  Future<void> _loadStarterReward() async {
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) return;
    try {
      final reward = await _api.fetchStarterReward(identityToken: token);
      if (!mounted) return;
      setState(() => _starterReward = reward);
      _maybeShowStarterRewardModal();
    } on ApiException catch (error) {
      // A 404 is an older backend: permanently hide this optional surface for
      // this screen. Other failures are equally nonblocking and retry on pull.
      if (error.statusCode != 404) return;
    } catch (_) {}
  }

  bool get _showStarterReward {
    final reward = _starterReward;
    if (reward == null ||
        reward['eligible'] != true ||
        reward['claimed'] == true) {
      return false;
    }
    final rewardRaceId = reward['raceId'] as String?;
    return rewardRaceId == null || rewardRaceId == widget.raceId;
  }

  /// Claims the starter reward. Returns true when the grant landed, so the
  /// modal knows to swap to its celebratory state; false means "close quietly"
  /// (already claimed, an older backend without the endpoint, or a failure
  /// that has already surfaced its own toast).
  Future<bool> _claimStarterReward() async {
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) return false;
    try {
      final result = await _api.claimStarterReward(identityToken: token);
      // Closes the activation funnel's reward stage (spec §5.9). Best-effort
      // and never awaited: telemetry must not sit between the grant landing
      // and the modal celebrating it.
      unawaited(_activationAnalytics.record('starter_reward_claimed'));
      final coins = (result['coins'] as num?)?.toInt();
      if (coins != null) await widget.authService.updateCoins(coins);
      if (!mounted) return false;
      setState(() {
        _starterReward = {
          ...?_starterReward,
          'claimed': true,
          'eligible': false,
        };
      });
      return result['granted'] == true;
    } on ApiException catch (error) {
      if (!mounted) return false;
      if (error.statusCode == 404) {
        setState(() => _starterReward = null);
      } else {
        showErrorToast(context, error.message);
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Shows the bonus once per screen visit, as soon as both the reward lookup
  /// and the race details have landed (they resolve independently). Guarded so
  /// the second caller to arrive is the one that opens it.
  void _maybeShowStarterRewardModal() {
    if (_starterRewardModalShown) return;
    if (!_showStarterReward) return;
    if ((_race?['status'] as String?) != 'ACTIVE') return;
    _starterRewardModalShown = true;
    _showStarterRewardModal();
  }

  /// One dialog, one appearance: claiming closes it (owner decision — no
  /// swapped-in "claimed" face, which read as a second 100-coin offer). A
  /// toast confirms the grant after the pop. `claiming` is local to this
  /// closure — the dialog owns it via StatefulBuilder, since a screen-level
  /// setState does not rebuild a route sitting above it.
  Future<void> _showStarterRewardModal() {
    final amount = (_starterReward?['amount'] as num?)?.toInt() ?? 100;
    var claiming = false;

    return _runRaceOverlay(() async {
      if (!mounted || _race?['status'] != 'ACTIVE') return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.62),
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setModalState) => Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 24),
            child: GameContainer(
              padding: const EdgeInsets.all(28),
              frameColor: AppColors.of(context).accent,
              surfaceColor: AppColors.of(context).parchmentLight,
              glowColor: AppColors.of(context).coinMid,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SpinningCoin(size: 54),
                  const SizedBox(height: 14),
                  Text(
                    'FIRST RACE BONUS',
                    textAlign: TextAlign.center,
                    style: PixelText.title(
                      size: 22,
                      color: AppColors.of(context).textDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'A little fuel for your Bara debut.',
                    textAlign: TextAlign.center,
                    style: PixelText.body(
                      size: 14,
                      color: AppColors.of(context).textMid,
                    ),
                  ),
                  const SizedBox(height: 20),
                  PillButton(
                    key: const Key('claim-starter-reward'),
                    label: claiming ? 'CLAIMING...' : 'CLAIM $amount COINS',
                    fullWidth: true,
                    onPressed: claiming
                        ? null
                        : () async {
                            setModalState(() => claiming = true);
                            final granted = await _claimStarterReward();
                            if (!dialogContext.mounted) return;
                            // Close either way: a refused claim has already
                            // toasted (or is simply an old backend); a granted
                            // one confirms via the toast below.
                            Navigator.of(dialogContext).pop();
                            if (granted && mounted) {
                              showInfoToast(context, '+$amount coins added.');
                            }
                          },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _appResumed = false;
      _backgroundedSinceLastResume = true;
      _impactAttemptGeneration += 1;
      _leaderboardWasVisible = false;
    } else if (state == AppLifecycleState.resumed) {
      _appResumed = true;
      _scheduleLeaderboardVisibilityCheck();
    }
    switch (racePollLifecycleAction(state, wasPolling: _pollingActive)) {
      case RacePollLifecycleAction.pause:
        // Off-screen: stop the network poll AND the 1s countdown ticker. The
        // ticker only drives UI (setState of _countdownNow), so ticking it
        // while backgrounded is wasted work; both are restarted on resume via
        // the flags below. The flags stay set so resume knows to restart.
        _pollTimer?.cancel();
        _countdownTimer?.cancel();
        _streams?.pause();
        break;
      case RacePollLifecycleAction.resume:
        // Foreground again after having polled: fetch once immediately for an
        // instant catch-up (the seq guard in _loadProgress keeps ordering
        // correct), then restart the periodic poll. _startPolling re-guards
        // its own timer.
        final genuineForegroundResume = _backgroundedSinceLastResume;
        _backgroundedSinceLastResume = false;
        if (_routeVisible || _raceOverlayPending > 0) {
          unawaited(
            _refreshAfterCoverage(
              deliverImpactNotices: genuineForegroundResume,
            ),
          );
        }
        break;
      case RacePollLifecycleAction.none:
        break;
    }
    // Restart the countdown ticker on any resume where it was running — covers
    // both ACTIVE races (which also resumed polling above) and PENDING
    // scheduled races (which tick a countdown but never poll).
    if (state == AppLifecycleState.resumed &&
        _routeVisible &&
        _countdownActive) {
      _startCountdown();
    }
  }

  // The composer lives inside the page's SingleChildScrollView, so the
  // keyboard can open with the field scrolled out of view; once the keyboard
  // animation has settled, scroll it back to just above the keyboard.
  void _onComposerFocusChanged() {
    if (!_messageFocus.hasFocus) return;
    Future.delayed(const Duration(milliseconds: 350), () {
      if (!mounted || !_messageFocus.hasFocus) return;
      final ctx = _messageFocus.context;
      if (ctx == null || !ctx.mounted) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 1.0,
        duration: const Duration(milliseconds: 150),
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    appRouteObserver.unsubscribe(this);
    // Only dispose a controller we created; an injected one belongs to the
    // caller (tests).
    if (widget.boxRerollAdController == null) _rerollAdCtrl?.dispose();
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    _messageInput.dispose();
    _messageFocus.dispose();
    _streams?.dispose();
    super.dispose();
  }

  void _ensureChatInitialized({bool poll = true}) {
    // Chat 403s a non-participant preview viewer; the tab renders locked.
    if (_isPreviewViewer) return;
    final streams = _streams;
    if (streams == null) return;
    if (_chatInitialized) {
      _chat = streams.chat;
      return;
    }
    _chatInitialized = true;
    unawaited(
      streams.openChat(muted: _race?['myChatMuted'] == true).then((_) {
        if (!mounted) return;
        _chat = streams.chat;
        setState(() {});
      }),
    );
    _chat = streams.chat;
  }

  void _ensureFeedInitialized({bool poll = true}) {
    if (_feedInitialized) return;
    if (_race == null) return;
    // Belt-and-braces: the activity feed 403s a non-participant preview viewer.
    if (_isPreviewViewer) return;
    if (!_routeVisible || !_appResumed) return;
    _feedInitialized = true;
    final streams = RaceStreamCoordinator(
      authService: widget.authService,
      raceId: widget.raceId,
      api: widget.backendApiService,
    );
    _streams = streams;
    _feed = streams.feed;
    streams.addListener(_onStreamsChanged);
    unawaited(
      streams.initialize(live: poll, muted: _race?['myChatMuted'] == true),
    );
  }

  void _onStreamsChanged() {
    if (!mounted) return;
    final streams = _streams;
    _chat = streams?.chat;
    if (streams?.chatHasUnread == true && _activityTabIndex != 1) {
      _chatHasUnread = true;
    }
    setState(() {});
  }

  void _onTabChanged(int index) {
    if (_activityTabIndex == index) return;
    setState(() => _activityTabIndex = index);
    if (index == 1) {
      // Switched to Chat: clear unread + persist read state on the server.
      _chatHasUnread = false;
      if (_chatInitialized) {
        _streams?.setChatVisible(true);
      } else {
        _ensureChatInitialized(poll: _pollingActive);
      }
    } else {
      // Switched away from Chat: persist read state.
      _streams?.setChatVisible(false);
      _chat?.markRead();
    }
  }

  Future<void> _loadDetails() => _detailsInFlight ??= _loadDetailsImpl()
      .whenComplete(() => _detailsInFlight = null);

  Future<void> _refreshDetailsFromPull() async {
    await _loadDetails();
    await _streams?.refreshNow();
    await _streams?.refreshPrivateActivity();
  }

  Future<void> _loadDetailsImpl() async {
    try {
      final token = widget.authService.authToken;
      if (token == null || token.isEmpty) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _authMissing = true;
          });
        }
        return;
      }
      _authMissing = false;

      final bootstrap = await _api.fetchRaceBootstrap(
        identityToken: token,
        raceId: widget.raceId,
        // Ask the race-open packet for just the first page. Without this the
        // packet carries the entire field, `_loadProgress` is satisfied by it,
        // and the paged request below never runs — which is why paging looked
        // like it did nothing.
        participantsLimit: _kParticipantsPageSize,
      );
      Map<String, dynamic> details;
      Future<Map<String, dynamic>?>? progressPrefetch;
      var bootstrapProgressUnavailable = false;
      if (bootstrap.supported && bootstrap.race != null) {
        details = bootstrap.race!;
        progressPrefetch = Future.value(bootstrap.progress);
        bootstrapProgressUnavailable = bootstrap.progressUnavailable;
        _applyGlobalPowerupInventory(bootstrap.globalPowerupInventory);
      } else {
        // Frozen backend: restore the existing parallel detail/progress path.
        progressPrefetch = _api
            .fetchRaceProgress(identityToken: token, raceId: widget.raceId)
            .then((progress) => progress as Map<String, dynamic>?)
            .catchError((_) => null);
        details = await _api.fetchRaceDetails(
          identityToken: token,
          raceId: widget.raceId,
          // Same one-page ask the bootstrap route gets. A backend that doesn't
          // honour this build's capability token ignores it and answers whole.
          participantsLimit: _kParticipantsPageSize,
        );
        if (details['status'] == 'ACTIVE') {
          unawaited(_loadGlobalPowerupInventory(token));
        }
      }

      if (!mounted) return;
      final isInitialRouteLoad = !_initialDetailsLoadCompleted;
      _initialDetailsLoadCompleted = true;
      final previousRaceStatus = _race?['status'];
      setState(() {
        _race = details;
        _isLoading = false;
        _detailsError = null;
        // One mute covers both placement and chat; treat the race as muted if
        // either flag is set. Defaults false for older backends missing the keys.
        _placementMuted =
            details['myPlacementAlertsMuted'] == true ||
            details['myChatMuted'] == true;
      });
      if (previousRaceStatus == 'ACTIVE' && details['status'] != 'ACTIVE') {
        unawaited(_streams?.replacePrivateActivity());
      }

      // Preview mode (a non-participant on a public, non-tournament race) is a
      // SINGLE fetch plus pull-to-refresh: the backend's read-only preview path
      // is built for occasional reads, and a 30s poll from every browser would
      // defeat it. Chat/activity are locked rather than fetched — those
      // endpoints still 403 a non-participant.
      final previewViewer = _isPreviewViewer;

      if (details['status'] == 'ACTIVE') {
        setState(() {
          _participantsTotal = null;
          // Re-opening a race starts at the top of the board, never wherever
          // the last visit happened to be paged to.
          _participantsOffset = 0;
          _participantsHasMore = false;
          _participantsLoadingMore = false;
        });
        _maybeShowStarterRewardModal();
        if (bootstrapProgressUnavailable) {
          setState(() {
            _progressState = const Loadable.error(
              'Couldn’t load race progress. Please try again.',
            );
          });
        } else {
          unawaited(
            _loadActiveProgressAndImpactNotices(
              prefetched: progressPrefetch,
              refetchOnNullPrefetch: !bootstrap.supported,
              deliverImpactNotices: isInitialRouteLoad,
            ),
          );
        }
        if (!previewViewer) _startPolling();
        _startCountdown();
        if (!previewViewer) _ensureFeedInitialized();
      } else if (details['status'] == 'COMPLETED') {
        // Finished races keep their chat + activity viewable (read-only —
        // _canPostMessage is false and the backend rejects posts). Load once,
        // no polling: the conversation can't change anymore. The completed
        // progress contract is the authoritative, ordered final roster; never
        // render the (possibly paged) details array as a final standings board.
        setState(() {
          _participantsTotal = null;
          _participantsOffset = 0;
          _participantsHasMore = false;
          _participantsLoadingMore = false;
        });
        unawaited(
          _loadCompletedProgress(
            prefetched: progressPrefetch,
            refetchOnNullPrefetch: !bootstrap.supported,
          ),
        );
        if (!previewViewer) _ensureFeedInitialized(poll: false);
      } else if (details['status'] == 'PENDING') {
        // Scheduled races show a live countdown to their auto-start; the
        // ticker otherwise only runs for ACTIVE races.
        final scheduled = DateTime.tryParse(
          details['scheduledStartAt'] as String? ?? '',
        );
        if (scheduled != null && scheduled.isAfter(DateTime.now())) {
          _startCountdown();
        }
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      // 403 is the backend's "you are not a participant in this race". It is a
      // state, not a failure — say so once instead of toasting the raw message
      // over an empty board.
      if (e.statusCode == 403) {
        _enterNotAParticipant();
        return;
      }
      setState(() {
        _isLoading = false;
        _detailsError = e.message;
      });
      showErrorToast(context, e.message);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _detailsError = e.toString();
        });
        showErrorToast(context, e.toString());
      }
    }
  }

  Future<void> _loadActiveProgressAndImpactNotices({
    Future<Map<String, dynamic>?>? prefetched,
    required bool refetchOnNullPrefetch,
    required bool deliverImpactNotices,
  }) async {
    await _loadProgress(
      prefetched: prefetched,
      refetchOnNullPrefetch: refetchOnNullPrefetch,
    );
    if (deliverImpactNotices) await _attemptActiveImpactDelivery();
  }

  Future<void> _loadCompletedProgress({
    Future<Map<String, dynamic>?>? prefetched,
    required bool refetchOnNullPrefetch,
  }) => _loadProgress(
    prefetched: prefetched,
    refetchOnNullPrefetch: refetchOnNullPrefetch,
  );

  Future<void> _attemptActiveImpactDelivery() async {
    if (!mounted ||
        widget.demoMode ||
        _notAParticipant ||
        _race?['status'] != 'ACTIVE' ||
        _progress?['status'] != 'ACTIVE' ||
        _race?['myStatus'] != 'ACCEPTED') {
      return;
    }
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) return;
    final storedImpactBaseline = await _readImpactBaseline();
    final impactBaseline = storedImpactBaseline ?? DateTime.now().toUtc();

    final attempt = ++_impactAttemptGeneration;
    await _streams?.refreshPrivateActivity();
    if (!_impactAttemptStillCurrent(attempt, token)) return;
    try {
      var result = await _api.fetchActiveRaceImpactNotices(
        identityToken: token,
        raceId: widget.raceId,
        resolvedAfter: impactBaseline,
      );
      if (!_impactAttemptStillCurrent(attempt, token)) return;

      if (result.isPending) {
        final succeeded = await _awaitActiveImpactResolution(
          result,
          attempt: attempt,
          identityToken: token,
        );
        if (!succeeded || !_impactAttemptStillCurrent(attempt, token)) return;
        // Exactly one retry after a successful bounded handoff. A second 202
        // ends this attempt; the next genuine open/resume may try again.
        result = await _api.fetchActiveRaceImpactNotices(
          identityToken: token,
          raceId: widget.raceId,
          resolvedAfter: impactBaseline,
        );
        if (!_impactAttemptStillCurrent(attempt, token) || result.isPending) {
          return;
        }
      }

      final notices = result.notices
          .map(_ActiveImpactNotice.tryParse)
          .whereType<_ActiveImpactNotice>()
          .where(_isPopupEligibleImpact)
          .toList(growable: false);
      if (result.authoritative && storedImpactBaseline == null) {
        await _writeImpactBaseline(impactBaseline);
      }
      final noticesToPresent = result.resolvedAfterApplied
          ? _filterPreReleaseImpactNotices(notices, baseline: impactBaseline)
          : notices;
      if (noticesToPresent.isEmpty) return;
      if (noticesToPresent.any(
        (notice) => _feed?.containsEvent(notice.id) != true,
      )) {
        await _streams?.refreshPrivateActivity();
      }
      if (!_impactAttemptStillCurrent(attempt, token)) return;
      if (!mounted) return;
      final successAccent = AppColors.grassDark;
      final errorAccent = AppColors.error;
      await _runRaceOverlay(() async {
        for (final notice in noticesToPresent) {
          if (!mounted || !_canPresentActiveImpact(attempt: attempt)) {
            return;
          }
          final accent = notice.deltaSteps > 0 ? successAccent : errorAccent;
          await showPowerupRevealModal(
            context,
            iconType: notice.powerupType,
            title: 'POWERUP SUMMARY',
            subtitle: notice.description ?? 'Your race steps changed.',
            signedSteps: notice.deltaSteps,
            accent: accent,
          );
          if (!_impactAttemptStillCurrent(attempt, token)) return;
          await _api.acknowledgeActiveRaceImpactNotice(
            identityToken: token,
            raceId: widget.raceId,
            noticeId: notice.id,
          );
        }
      });
    } catch (_) {
      // Capability disabled/old backend/unauthorized viewer all degrade to no
      // overlay. The private endpoint remains the actual security boundary.
    }
  }

  String get _impactBaselineKey {
    final account =
        widget.authService.userId ??
        widget.authService.identityToken ??
        'anonymous';
    return 'active_impact_notification_baseline_v1_$account';
  }

  Future<DateTime?> _readImpactBaseline() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_impactBaselineKey);
    return stored == null ? null : DateTime.tryParse(stored);
  }

  Future<void> _writeImpactBaseline(DateTime baseline) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_impactBaselineKey, baseline.toIso8601String());
  }

  List<_ActiveImpactNotice> _filterPreReleaseImpactNotices(
    List<_ActiveImpactNotice> notices, {
    required DateTime baseline,
  }) {
    return notices
        .where((notice) => notice.resolvedAt.isAfter(baseline))
        .toList();
  }

  bool _impactAttemptStillCurrent(int attempt, String identityToken) =>
      mounted &&
      attempt == _impactAttemptGeneration &&
      identityToken == widget.authService.authToken &&
      _appResumed &&
      !_notAParticipant &&
      _race?['status'] == 'ACTIVE' &&
      _progress?['status'] == 'ACTIVE';

  Future<bool> _awaitActiveImpactResolution(
    ActiveImpactNoticesResult pending, {
    required int attempt,
    required String identityToken,
  }) async {
    final jobId = pending.jobId;
    final generation = pending.generation;
    final firstDelayMs = pending.retryAfterMs;
    if (jobId == null || generation == null || firstDelayMs == null) {
      return false;
    }
    final schedule = <Duration>[
      Duration(milliseconds: firstDelayMs),
      const Duration(milliseconds: 1500),
      const Duration(seconds: 3),
      const Duration(seconds: 5),
    ];
    for (final delay in schedule) {
      await Future<void>.delayed(delay);
      if (!_impactAttemptStillCurrent(attempt, identityToken)) return false;
      final status = await _api.fetchRaceResolutionStatus(
        identityToken: identityToken,
        jobId: jobId,
        generation: generation,
      );
      if (!_impactAttemptStillCurrent(attempt, identityToken)) return false;
      if (status.isSucceeded) return true;
      if (status.isTerminal) return false;
    }
    return false;
  }

  /// Switch the screen to the not-a-participant state and shut every poller
  /// down. Called from the details load and from the 30s progress poll, so a
  /// mid-session prune stops the loop instead of erroring every 30s forever.
  void _enterNotAParticipant() {
    _pollingActive = false;
    _countdownActive = false;
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    _chat?.stopPolling();
    _feed?.stopPolling();
    _streams?.pause();
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _notAParticipant = true;
    });
  }

  Future<void> _loadProgress({
    Future<Map<String, dynamic>?>? prefetched,
    bool refetchOnNullPrefetch = true,
    bool append = false,
  }) async {
    // Ordering guard: concurrent fetches (30s poll vs the refresh fired right
    // after opening a box) can resolve out of order, and a stale snapshot
    // landing last used to overwrite the fresh one — an opened mystery box
    // would visibly "un-open" until the next poll. Only the newest-issued
    // request may commit its response.
    final fetchSeq = ++_progressFetchSeq;
    final previous = _progress;
    if (mounted) {
      if (append) {
        setState(() => _participantsLoadingMore = true);
      } else {
        setState(() {
          _progressState = previous == null
              ? const Loadable.loading()
              : Loadable.refreshing(previous);
        });
      }
    }

    try {
      final token = widget.authService.authToken;
      if (token == null || token.isEmpty) {
        if (mounted) {
          setState(() {
            _progressState = Loadable.error('Not signed in.', data: previous);
            _participantsLoadingMore = false;
          });
        }
        return;
      }

      // A prefetched result (fired in parallel with details) is used when it
      // succeeded; a failed prefetch falls back to a fresh request so errors
      // still surface through the normal path below.
      final prefetchedProgress = prefetched != null ? await prefetched : null;
      if (prefetched != null &&
          prefetchedProgress == null &&
          !refetchOnNullPrefetch) {
        throw const ApiException(
          'Couldn’t load race progress. Please try again.',
        );
      }
      RaceProgressResult? compactResult;
      // One page in flight, always: a refresh or poll re-reads the page the
      // viewer is on rather than snapping them back to the top.
      final requestedOffset = append ? _participantsOffset : 0;
      final requestedLimit = _kParticipantsPageSize;
      final progress =
          prefetchedProgress ??
          (compactResult = await _api.fetchRaceProgressParticipants(
            identityToken: token,
            raceId: widget.raceId,
            offset: requestedOffset,
            limit: requestedLimit,
          )).progress;

      if (compactResult?.hasCompactInventory == true) {
        _applyGlobalPowerupInventory(compactResult?.globalPowerupInventory);
      }

      if (!mounted) return;
      final participants =
          (progress['participants'] as List?)
              ?.whereType<Map>()
              .map(
                (row) => <String, dynamic>{
                  for (final entry in row.entries)
                    if (entry.key is String) entry.key as String: entry.value,
                },
              )
              .toList(growable: false) ??
          const <Map<String, dynamic>>[];
      // The paged fetch supplies this directly; when a prefetched race-open
      // packet satisfied the request instead, its own metadata rides along
      // inside the progress payload. Null on either path (an older backend,
      // or a full non-paged response) leaves the list unpaged, which is the
      // pre-existing behaviour.
      final pagination =
          compactResult?.participantsPagination ??
          (progress['pagination'] is Map
              ? Map<String, dynamic>.from(progress['pagination'] as Map)
              : null);
      final existingParticipants =
          (previous?['participants'] as List?)
              ?.whereType<Map>()
              .map(
                (row) => <String, dynamic>{
                  for (final entry in row.entries)
                    if (entry.key is String) entry.key as String: entry.value,
                },
              )
              .toList(growable: false) ??
          const <Map<String, dynamic>>[];
      // A paged response IS the board: it replaces what was on screen, so
      // NEXT/PREV land on a page of exactly one page's height. Only an
      // UNPAGED response (older backend, or a race served whole) keeps the
      // old union behaviour, where dropping a row the server omitted this
      // tick would make racers flicker in and out.
      final mergedParticipants = pagination != null
          ? participants
          : () {
              final merged = [...participants];
              final currentIds = {
                for (final p in participants)
                  if (p['userId'] is String) p['userId'] as String,
              };
              for (final p in existingParticipants) {
                final userId = p['userId'];
                if (userId is! String) continue;
                if (!currentIds.contains(userId)) {
                  merged.add(p);
                }
              }
              return merged;
            }();

      final rawTotal = pagination?['total'];
      final totalFromServer = rawTotal is int
          ? rawTotal
          : rawTotal is num
          ? rawTotal.toInt()
          : int.tryParse(rawTotal?.toString() ?? '');
      // Trust the server's echoed offset over the local guess: a clamped or
      // rejected page must not leave the readout claiming a window the
      // response does not contain.
      final rawOffset = pagination?['offset'];
      final offsetFromServer = rawOffset is int
          ? rawOffset
          : rawOffset is num
          ? rawOffset.toInt()
          : null;

      final resolvedProgress = Map<String, dynamic>.from(progress)
        ..['participants'] = mergedParticipants;

      if (fetchSeq == _progressFetchSeq) {
        setState(() {
          _progress = resolvedProgress;
          _participantsTotal = totalFromServer;
          if (pagination != null) {
            _participantsOffset = offsetFromServer ?? requestedOffset;
          }
          _participantsHasMore =
              pagination?['hasMore'] == true ||
              (totalFromServer != null &&
                  _participantsOffset + mergedParticipants.length <
                      totalFromServer);
          _participantsLoadingMore = false;
          final rawPowerupData = resolvedProgress['powerupData'];
          _powerupData = rawPowerupData is Map
              ? <String, dynamic>{
                  for (final entry in rawPowerupData.entries)
                    if (entry.key is String) entry.key as String: entry.value,
                }
              : null;
          final rawEvent = resolvedProgress['globalEvent'];
          _globalEvent = rawEvent is Map
              ? <String, dynamic>{
                  for (final entry in rawEvent.entries)
                    if (entry.key is String) entry.key as String: entry.value,
                }
              : null;
          _progressState = Loadable.success(resolvedProgress);
        });
      }

      if (_powerupData?['enabled'] == true) {
        // A compact progress response carries the 30-second global inventory.
        // Legacy/malformed responses retain the standalone refresh.
        if (compactResult?.hasCompactInventory != true) {
          _loadGlobalPowerupInventory(token);
        }

        _queuedBoxCount = _readInt(
          _powerupData?['queuedBoxCount'],
          fallback: 0,
        );
        final newBoxes = (_powerupData?['newMysteryBoxes'] as List?) ?? [];
        final newQueued = _readInt(
          _powerupData?['newQueuedBoxes'],
          fallback: 0,
        );
        if (newBoxes.length == 1) {
          showInfoToast(context, 'You earned a mystery box!');
        } else if (newBoxes.length > 1) {
          showInfoToast(
            context,
            'You earned ${newBoxes.length} mystery boxes!',
          );
        }
        if (newQueued > 0) {
          showInfoToast(
            context,
            '$newQueued mystery box${newQueued > 1 ? 'es' : ''} queued. Inventory full',
          );
        }
      }

      if (progress['status'] == 'COMPLETED') {
        // Polling stops for good — clear the flags so a later app resume does
        // not restart the poll/countdown on a now-finished race.
        _pollingActive = false;
        _countdownActive = false;
        _pollTimer?.cancel();
        _countdownTimer?.cancel();
        _loadDetails();
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 403) {
        _enterNotAParticipant();
        return;
      }
      if (fetchSeq == _progressFetchSeq) {
        setState(() {
          _progressState = Loadable.error(e.message, data: previous);
        });
      }
      if (append) {
        setState(() {
          _participantsLoadingMore = false;
        });
      }
      if (previous != null) {
        showErrorToast(context, 'Couldn’t refresh race progress.');
      }
    } catch (e) {
      if (!mounted) return;
      if (fetchSeq == _progressFetchSeq) {
        setState(() {
          _progressState = Loadable.error(e.toString(), data: previous);
        });
      }
      if (append) {
        setState(() {
          _participantsLoadingMore = false;
        });
      }
      if (previous != null) {
        showErrorToast(context, 'Couldn’t refresh race progress.');
      }
    } finally {
      if (mounted && append) {
        setState(() {
          _participantsLoadingMore = false;
        });
      }
    }
  }

  Future<void> _refreshWallet() async {
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) return;

    final user = await _api.fetchMe(identityToken: token);
    await widget.authService.updateCoins(
      _readInt(user['coins'], fallback: widget.authService.coins),
    );
    await widget.authService.updateHeldCoins(
      _readInt(user['heldCoins'], fallback: widget.authService.heldCoins),
    );
  }

  void _startPolling() {
    _pollingActive = true;
    _pollTimer?.cancel();
    if (!_routeVisible || !_appResumed) return;
    // The demo's clock is floored at 0:20 (§5.5), but `endsAt` is read from the
    // race DETAILS payload, which the live screen fetches exactly once. A slow
    // reader would therefore watch the local 1s ticker run past 0:00 while the
    // engine still says 0:20. So in demoMode the poll re-pins details as well,
    // on a shorter interval. The engine guarantees the value never rises, so
    // re-pinning can only ever hold the clock — it can never jump it forward.
    _pollTimer = Timer.periodic(
      widget.demoMode
          ? const Duration(seconds: 3)
          : const Duration(seconds: 30),
      (_) {
        if (widget.demoMode) {
          _loadDetails();
        } else {
          _loadProgress();
        }
      },
    );
  }

  void _startCountdown() {
    _countdownActive = true;
    _countdownTimer?.cancel();
    if (!_routeVisible || !_appResumed) return;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _countdownNow = DateTime.now());
    });
  }

  /// Legacy-only. Funded races cost nothing, so accepting is a single tap and
  /// this sheet never appears. It survives for one case: a race created before
  /// app-funded pools that still holds real buy-ins — charging someone's coins
  /// without asking would be the worse bug.
  Future<bool> _confirmPaidInvite({required bool activeRace}) async {
    final buyInAmount = _readInt(_race?['buyInAmount'], fallback: 0);
    if (buyInAmount <= 0 || _prizePool != null) {
      return true;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: TrailSign(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$buyInAmount GOLD BUY-IN',
                style: PixelText.title(
                  size: 18,
                  color: AppColors.of(context).textDark,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                activeRace
                    ? 'Your $buyInAmount gold goes straight into the live pot.'
                    : 'Your $buyInAmount gold will be held until the race starts.',
                style: PixelText.body(
                  size: 14,
                  color: AppColors.of(context).textMid,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                activeRace
                    ? 'This race is already underway. You will need to catch up when you join.'
                    : 'You can only get this gold back if the race is cancelled.',
                style: PixelText.body(
                  size: 13,
                  color: AppColors.of(context).textMid,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              PillButton(
                label: 'LOCK IT IN',
                variant: PillButtonVariant.primary,
                fullWidth: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                onPressed: () => Navigator.of(context).pop(true),
              ),
              const SizedBox(height: 10),
              PillButton(
                label: 'BACK',
                variant: PillButtonVariant.accent,
                fullWidth: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ],
          ),
        ),
      ),
    );

    return result ?? false;
  }

  Future<void> _respondToInvite(bool accept) async {
    if (_isActing) return;
    setState(() {
      _isActing = true;
      _acceptingInvite = accept;
    });
    try {
      final token = widget.authService.authToken;
      if (token == null || token.isEmpty) return;

      if (accept) {
        final isActiveRace = (_race?['status'] as String?) == 'ACTIVE';
        final confirmed = await _confirmPaidInvite(activeRace: isActiveRace);
        if (!confirmed) {
          return;
        }
      }

      await _api.respondToRaceInvite(
        identityToken: token,
        raceId: widget.raceId,
        accept: accept,
      );
      await _refreshWallet();

      if (!mounted) return;

      if (accept) {
        showInfoToast(context, 'You joined the race!');
        _loadDetails();
      } else {
        Navigator.of(context).pop(true);
      }
    } on ApiException catch (e) {
      if (mounted) showErrorToast(context, fundedExposureErrorCopy(e));
    } catch (_) {
      if (mounted) {
        showErrorToast(context, 'Could not answer this invite. Try again.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isActing = false;
          _acceptingInvite = null;
        });
      }
    }
  }

  /// TR-802: a tap on an empty lobby peg. ACCEPTED members switch sides
  /// (TR-203); INVITED members accept onto that side (TR-201). Errors map
  /// through the playful team-race copy (TEAM_FULL etc.).
  Future<void> _onLobbySlotTap(RaceTeam team) async {
    if (_isActing) return;
    final myStatus = _race?['myStatus'] as String? ?? '';
    final myTeam = _myLobbyTeam();
    if (myStatus == 'ACCEPTED' && myTeam == team) return; // already there
    setState(() => _isActing = true);
    try {
      final token = widget.authService.authToken;
      if (token == null || token.isEmpty) return;

      if (myStatus == 'INVITED') {
        final confirmed = await _confirmPaidInvite(activeRace: false);
        if (!confirmed) return;
        await _api.acceptTeamRaceInvite(
          identityToken: token,
          raceId: widget.raceId,
          team: team.wireValue,
        );
        await _refreshWallet();
        if (mounted) showInfoToast(context, 'You joined the race!');
      } else if (myStatus == 'ACCEPTED') {
        await _api.setRaceTeam(
          identityToken: token,
          raceId: widget.raceId,
          team: team.wireValue,
        );
      } else {
        return;
      }
      await _loadDetails();
    } on ApiException catch (e) {
      if (mounted) {
        showErrorToast(
          context,
          e.code != null ? teamRaceErrorCopy(e.code) : e.message,
        );
      }
    } catch (e) {
      if (mounted) showErrorToast(context, e.toString());
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  /// TR-207: both sides at their `teamSize` cap — a surplus invitee can't
  /// accept onto either side until someone leaves.
  bool _bothSidesFull() {
    final race = _race;
    if (race == null || !TeamRace.isTeamRace(race)) return false;
    final size = TeamRace.teamSize(race);
    if (size == null || size <= 0) return false;
    final (a, b) = _teamAcceptedCounts();
    return a >= size && b >= size;
  }

  /// ACCEPTED members per side. Prefers the additive summary fields — the
  /// `participants` array may be a page, and undercounting here would let a
  /// surplus invitee tap onto a side that's already full.
  (int, int) _teamAcceptedCounts() {
    final summaryA = _summaryTeamAAcceptedCount;
    final summaryB = _summaryTeamBAcceptedCount;
    if (summaryA != null && summaryB != null) return (summaryA, summaryB);
    final participants =
        (_race?['participants'] as List?)?.cast<Map<String, dynamic>>() ??
        const <Map<String, dynamic>>[];
    final accepted = participants
        .where((p) => p['status'] == 'ACCEPTED')
        .toList();
    return (
      accepted
          .where((p) => TeamRace.participantTeam(p) == RaceTeam.teamA)
          .length,
      accepted
          .where((p) => TeamRace.participantTeam(p) == RaceTeam.teamB)
          .length,
    );
  }

  RaceTeam? _myLobbyTeam() {
    // `myTeam` is served top-level exactly because my own row may be off-page.
    final myTeam = parseRaceTeam(_race?['myTeam']);
    if (myTeam != null) return myTeam;
    if (_serverHonouredParticipantsPaging) return null;
    final participants =
        (_race?['participants'] as List?)?.cast<Map<String, dynamic>>() ??
        const [];
    for (final participant in participants) {
      if (participant['userId'] == _myUserId) {
        return TeamRace.participantTeam(participant);
      }
    }
    return null;
  }

  /// Legacy team races predate the stamped generalized leave action. Keep
  /// their established controls only when the additive field is truly absent;
  /// an invalid non-null stamp must never be guessed into a mutation.
  bool get _hasNoLeaveActionStamp {
    final race = _race;
    return race != null &&
        (!race.containsKey('leaveAction') || race['leaveAction'] == null);
  }

  bool get _canLeaveLegacyTeamLobby {
    final race = _race;
    return !widget.demoMode &&
        !_isSpectator &&
        race != null &&
        race['tournamentId'] == null &&
        TeamRace.isTeamRace(race) &&
        race['status'] == 'PENDING' &&
        race['myStatus'] == 'ACCEPTED' &&
        race['isCreator'] != true &&
        _hasNoLeaveActionStamp;
  }

  bool _canForfeitLegacyTeamRace(List<Map<String, dynamic>> participants) {
    final race = _race;
    return !widget.demoMode &&
        !_isSpectator &&
        race != null &&
        race['tournamentId'] == null &&
        TeamRace.isTeamRace(race) &&
        race['status'] == 'ACTIVE' &&
        race['myStatus'] == 'ACCEPTED' &&
        race['isCreator'] != true &&
        _hasNoLeaveActionStamp &&
        !_iHaveForfeited(participants);
  }

  Future<void> _forfeitTeamRace() async {
    final myTeam = _myLobbyTeam();
    final teamName = myTeam != null
        ? TeamRace.teamName(_race ?? const {}, myTeam)
        : 'your team';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        child: TrailSign(
          width: 330,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'FORFEIT THE RACE?',
                style: PixelText.title(
                  size: 18,
                  color: AppColors.of(context).textDark,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              _forfeitConsequence(
                Icons.ac_unit_rounded,
                'Your steps freeze now and stay with $teamName. They still count toward the team total.',
              ),
              const SizedBox(height: 10),
              _forfeitConsequence(
                Icons.money_off_rounded,
                'No refund. Your buy-in stays in the pot, and you get no cut even if your team wins.',
              ),
              const SizedBox(height: 10),
              _forfeitConsequence(
                Icons.block_rounded,
                "This is permanent. You can't rejoin this race.",
              ),
              const SizedBox(height: 18),
              PillButton(
                label: 'KEEP RACING',
                variant: PillButtonVariant.primary,
                fullWidth: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                onPressed: () => Navigator.of(dialogContext).pop(false),
              ),
              const SizedBox(height: 10),
              PillButton(
                label: 'FORFEIT ANYWAY',
                variant: PillButtonVariant.accent,
                fullWidth: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                onPressed: () => Navigator.of(dialogContext).pop(true),
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isActing = true);
    try {
      final token = widget.authService.authToken;
      if (token == null || token.isEmpty) return;
      await _api.forfeitRace(identityToken: token, raceId: widget.raceId);
      await _refreshWallet();
      await _loadDetails();
      await _loadProgress();
    } on ApiException catch (e) {
      if (mounted) {
        showErrorToast(
          context,
          e.code != null ? teamRaceErrorCopy(e.code) : e.message,
        );
      }
    } catch (e) {
      if (mounted) showErrorToast(context, e.toString());
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  Widget _forfeitConsequence(IconData icon, String text) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 16, color: AppColors.of(context).textMid),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          style: PixelText.body(
            size: 12.5,
            color: AppColors.of(context).textMid,
          ),
        ),
      ),
    ],
  );

  Future<void> _leaveTeamLobby() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        child: TrailSign(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'LEAVE THE LOBBY?',
                style: PixelText.title(
                  size: 18,
                  color: AppColors.of(context).textDark,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Your buy-in hold is released and your peg opens up. You can rejoin any time before the race starts.',
                style: PixelText.body(
                  size: 14,
                  color: AppColors.of(context).textMid,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: PillButton(
                      label: 'STAY',
                      variant: PillButtonVariant.secondary,
                      fontSize: 13,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 11,
                      ),
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: PillButton(
                      label: 'LEAVE',
                      variant: PillButtonVariant.accent,
                      fontSize: 13,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 11,
                      ),
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isActing = true);
    try {
      final token = widget.authService.authToken;
      if (token == null || token.isEmpty) return;
      await _api.leaveRace(identityToken: token, raceId: widget.raceId);
      await _refreshWallet();
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        showErrorToast(
          context,
          e.code != null ? teamRaceErrorCopy(e.code) : e.message,
        );
      }
    } catch (e) {
      if (mounted) showErrorToast(context, e.toString());
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  Future<void> _startRace() async {
    setState(() => _isActing = true);
    try {
      final token = widget.authService.authToken;
      if (token == null || token.isEmpty) return;

      await _api.startRace(identityToken: token, raceId: widget.raceId);
      await _refreshWallet();
      if (mounted) {
        showInfoToast(context, 'Race started!');
        _loadDetails();
      }
    } catch (e) {
      if (mounted) showErrorToast(context, e.toString());
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  void _showCancelConfirmation() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: TrailSign(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'CANCEL RACE',
                style: PixelText.title(
                  size: 18,
                  color: AppColors.of(context).textDark,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'This cannot be undone. Are you sure you want to cancel this race?',
                style: PixelText.body(
                  size: 14,
                  color: AppColors.of(context).textMid,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: PillButton(
                      label: 'GO BACK',
                      variant: PillButtonVariant.secondary,
                      fontSize: 13,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: PillButton(
                      label: 'CONFIRM',
                      variant: PillButtonVariant.accent,
                      fontSize: 13,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                        _cancelRace();
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editRaceSettings() async {
    final race = _race;
    if (race == null) return;
    final result = await Navigator.of(context).push<Map<String, dynamic>?>(
      MaterialPageRoute(
        builder: (_) => EditRaceScreen(
          authService: widget.authService,
          backendApiService: _api,
          raceId: widget.raceId,
          race: race,
          // Hand the true field sizes down: `race['participants']` may be a
          // page, and letting the editor re-derive from it would validate
          // maxParticipants/teamSize against an undercount.
          acceptedCount: _summaryAcceptedCount,
          teamAAcceptedCount: _summaryTeamAAcceptedCount,
          teamBAcceptedCount: _summaryTeamBAcceptedCount,
        ),
      ),
    );
    if (!mounted) return;
    if (result != null) {
      // Issue 4: a buy-in edit can refund/re-charge the owner, so refresh the
      // wallet alongside the race detail.
      await _refreshWallet();
      await _loadDetails();
    }
  }

  Future<void> _cancelRace() async {
    setState(() => _isActing = true);
    try {
      final token = widget.authService.authToken;
      if (token == null || token.isEmpty) return;

      await _api.cancelRace(identityToken: token, raceId: widget.raceId);
      await _refreshWallet();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showErrorToast(context, e.toString());
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  Future<void> _inviteMore() async {
    if (widget.friends.isEmpty) {
      showInfoToast(context, 'No friends available to invite');
      return;
    }

    // `participantUserIds` is the whole roster as bare ids, sent precisely
    // because `participants` may be a page — filtering against the page alone
    // re-offers friends who are already in the race. Falls back to the array
    // when the field is absent (older backend / unpaged response), reading
    // each id defensively rather than casting.
    final existingIds =
        _summaryParticipantUserIds?.toSet() ??
        {
          for (final p
              in (_race?['participants'] as List?)?.whereType<Map>() ??
                  const <Map>[])
            if (p['userId'] is String) p['userId'] as String,
        };

    final selectedIds = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (context) => RaceInviteScreen(
          friends: widget.friends,
          existingParticipantIds: existingIds,
          // TR-708: gray out friends who can't accept a team-race invite.
          teamRaceMode: TeamRace.isTeamRace(_race ?? const {}),
        ),
      ),
    );

    if (selectedIds == null || selectedIds.isEmpty || !mounted) return;

    setState(() => _isActing = true);
    try {
      final token = widget.authService.authToken;
      if (token == null || token.isEmpty) return;

      await _api.inviteToRace(
        identityToken: token,
        raceId: widget.raceId,
        inviteeIds: selectedIds,
      );

      if (mounted) {
        showInfoToast(context, 'Invites sent!');
        _loadDetails();
      }
    } catch (e) {
      if (mounted) showErrorToast(context, e.toString());
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  Future<void> _usePowerup(
    Map<String, dynamic> powerup, {
    int upgradeLevel = 0,
    String? targetEffectId,
  }) async {
    final type = powerup['type'] as String;
    // Store-redeemed items are distinguishable from race-earned drops even
    // after a prior app version left one in the tray: redemption creates them
    // with neither a rarity nor a milestone. The server returns these to the
    // global stash on a rejected use, so reconcile instead of restoring a
    // stale in-race snapshot.
    final wasRedeemedFromStash =
        powerup['rarity'] == null && powerup['earnedAtSteps'] == null;
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) return;

    String? targetUserId;
    List<String>? targetUserIds;
    String? targetDirection;

    var participants =
        (_progress?['participants'] as List?)?.cast<Map<String, dynamic>>() ??
        [];
    final needsTargetingContext =
        _participantsHasMore ||
        (_participantsTotal != null &&
            participants.length < _participantsTotal!);
    final typeTargets =
        type == 'QUICKSAND' ||
        type == 'PINECONE_TOSS' ||
        type == 'SNEAKY_SWAP' ||
        kTargetedPowerupTypes.contains(type);
    if (typeTargets && type != 'PINECONE_TOSS' && needsTargetingContext) {
      final useContextParticipants = await _loadRacePowerupTargetContext(
        token,
        type,
      );
      if (useContextParticipants.isNotEmpty) {
        participants = useContextParticipants;
      }
    }
    // TR-651/657: enemy-team members only (no friendly fire) and no
    // forfeiters — an invalid target is never presented. Individual races keep
    // today's "everyone but me, minus stealthed" pool.
    final targets = TeamRace.offensiveTargets(
      participants: participants,
      myUserId: _myUserId,
      race: _race ?? const {},
    );

    if (type == 'QUICKSAND') {
      if (targets.isEmpty) {
        if (mounted) showErrorToast(context, 'No targets available');
        return;
      }
      targetUserIds = await _showQuicksandTargetPicker(targets);
      if (targetUserIds == null) return;
    } else if (type == 'PINECONE_TOSS') {
      targetDirection = await _showPineconeDirectionPicker();
      if (targetDirection == null) return;
    } else if (type == 'SNEAKY_SWAP') {
      // Only offer racers who actually hold something stealable. New endpoint;
      // on an older backend (or any failure) fall back to all eligible racers.
      final swapTargets = await _resolveSneakySwapTargets(token, targets);
      if (swapTargets.isEmpty) {
        if (mounted) {
          showInfoToast(context, 'No one has a powerup to steal right now');
        }
        return;
      }
      // Steal redesign: pick a target and the server takes one RANDOM
      // stealable powerup from them — nothing of yours is given up, so the
      // old two-step SWAP AWAY / TAKE FROM TARGET pickers are gone.
      targetUserId = await _showTargetPicker(swapTargets, type);
      if (targetUserId == null) return;
    } else if (type == 'BOUNTY') {
      // §7 powerups5 — Bounty may only wager on a rival currently AHEAD of me.
      // Pre-filter the picker client-side (server still validates on a fresher
      // scoreline); never present a losing wager.
      var myTotalSteps = 0;
      for (final p in participants) {
        if ((p['userId'] as String?) == _myUserId) {
          myTotalSteps = (p['totalSteps'] as num?)?.toInt() ?? 0;
          break;
        }
      }
      final aheadTargets = TeamRace.targetsAheadOf(
        targets: targets,
        myTotalSteps: myTotalSteps,
      );
      if (aheadTargets.isEmpty) {
        if (mounted) {
          showInfoToast(context, 'No rivals are ahead of you to target');
        }
        return;
      }
      targetUserId = await _showTargetPicker(aheadTargets, type);
      if (targetUserId == null) return;
    } else if (kTargetedPowerupTypes.contains(type)) {
      if (targets.isEmpty) {
        if (mounted) {
          showErrorToast(
            context,
            TeamRace.isTeamRace(_race ?? const {})
                ? 'No enemy racers to target right now'
                : 'No targets available',
          );
        }
        return;
      }

      targetUserId = await _showTargetPicker(targets, type);
      if (targetUserId == null) return;
    }

    setState(() => _isActing = true);
    // Optimistically empty the slot the moment the user commits (mirrors the
    // optimistic coin deduction below) — on a slow connection the item used
    // to sit in the inventory until _loadProgress() returned, which read as
    // "it went back". Restored on failure.
    final restoreInventory = _optimisticallyRemoveFromInventory(
      powerup['id'] as String,
    );
    try {
      final result = type == 'QUICKSAND'
          ? await _api.useQuicksand(
              identityToken: token,
              raceId: widget.raceId,
              powerupId: powerup['id'] as String,
              targetUserIds: targetUserIds!,
            )
          : await _api.usePowerup(
              identityToken: token,
              raceId: widget.raceId,
              powerupId: powerup['id'] as String,
              targetUserId: targetUserId,
              targetDirection: targetDirection,
              targetEffectId: targetEffectId,
              upgradeLevel: upgradeLevel,
            );

      final res = result['result'] as Map<String, dynamic>?;
      final parsedReceipt = _ActiveImpactReceipt.tryParse(
        result['activeImpactReceipt'],
      );
      final activeImpactReceipt = parsedReceipt?.raceId == widget.raceId
          ? parsedReceipt
          : null;
      unawaited(_streams?.refreshPrivateActivity());
      final coinsSpent = _readInt(res?['coinsSpent'], fallback: 0);
      if (coinsSpent > 0) {
        await widget.authService.updateCoins(
          widget.authService.coins - coinsSpent,
        );
      }

      if (!mounted) return;

      // Read the outcome defensively: an older backend only returns `blocked`,
      // a newer one also returns the `outcome` discriminator + `reflected`.
      // Blocked/Reflected get a reveal-style modal (matching the mystery-box
      // UNBOX reveal); a normal/APPLIED outcome keeps the success toast.
      final outcome = attackOutcomeFromResult(res);
      var inlineModalDismissed = false;
      var inlineToastAckScheduled = false;

      void showOutcomeToast(String message) {
        inlineToastAckScheduled = activeImpactReceipt != null;
        showInfoToast(
          context,
          message,
          onDismissed: activeImpactReceipt == null
              ? null
              : () => unawaited(
                  _acknowledgeActiveImpactReceipt(
                    activeImpactReceipt,
                    identityToken: token,
                  ),
                ),
        );
      }

      if (type == 'QUICKSAND') {
        await _runRaceOverlay(() => _showQuicksandResults(res, targets));
        inlineModalDismissed = true;
      } else if (type == 'DEFENSE_SCAN') {
        // X-Ray is an instantaneous intel read: the reveal rides back on the
        // use response as `scan` (contract puts it top-level; also check the
        // nested result for backend variance). Degrade safely if it's absent
        // (older backend that consumed the item but returns no snapshot).
        final scan =
            (result['scan'] as Map<String, dynamic>?) ??
            (res?['scan'] as Map<String, dynamic>?);
        await _runRaceOverlay(() => _showDefenseScanSheet(scan));
        inlineModalDismissed = true;
      } else if (outcome == AttackOutcome.blocked ||
          outcome == AttackOutcome.reflected ||
          outcome == AttackOutcome.redirected ||
          outcome == AttackOutcome.reflectedBlocked) {
        // Blocked / Reflected / Decoy-redirected / reflected-then-blocked all
        // get the reveal modal.
        await _runRaceOverlay(
          () => showAttackOutcomeModal(context, res ?? const {}),
        );
        inlineModalDismissed = true;
      } else if (type == 'COIN_FLIP') {
        // Server-rolled 2x/0.5x. A missing `flip` (older backend) degrades to
        // the generic toast below rather than a blank reveal.
        final reveal = CoinFlipReveal.fromResult(res);
        if (reveal != null) {
          await _runRaceOverlay(
            () => showPowerupRevealModal(
              context,
              iconType: 'COIN_FLIP',
              title: reveal.won ? 'HEADS!' : 'TAILS!',
              subtitle: reveal.won
                  ? 'Your steps are doubled for the next hour!'
                  : 'Tough luck. Your steps are halved for the next hour.',
              accent: reveal.won
                  ? AppColors.of(context).coinDark
                  : AppColors.of(context).error,
            ),
          );
          inlineModalDismissed = true;
        } else {
          showOutcomeToast('${PowerupCopy.nameFor(type)} activated!');
        }
      } else if (type == 'MYSTERY_POTION') {
        // Server-rolled outcome. A missing `rolled` degrades to generic toast.
        final reveal = MysteryPotionReveal.fromResult(res);
        if (reveal != null) {
          await _runRaceOverlay(
            () => showPowerupRevealModal(
              context,
              iconType: reveal.iconType,
              title: 'MYSTERY POTION',
              subtitle: reveal.subtitle(),
            ),
          );
          inlineModalDismissed = true;
        } else {
          showOutcomeToast('${PowerupCopy.nameFor(type)} activated!');
        }
      } else if (type == 'UPRISING' ||
          type == 'POWER_OUTAGE' ||
          type == 'RALLY_FLAG') {
        // AoE / team fan-outs report how many racers they touched. `affected`
        // is additive — absent on an older backend → plain activation toast.
        final affected = _readInt(res?['affected'], fallback: -1);
        final name = PowerupCopy.nameFor(type);
        showOutcomeToast(
          affected >= 0
              ? '$name activated. $affected racer${affected == 1 ? '' : 's'} affected!'
              : '$name activated!',
        );
      } else if (type == 'SNEAKY_SWAP') {
        // Reveal what was stolen. Additive field — older backends (mutual
        // swap) return no stolenPowerup, so fall back to the generic toast.
        final stolen = res?['stolenPowerup'] as Map<String, dynamic>?;
        final stolenType = stolen?['type'] as String?;
        showOutcomeToast(
          stolenType != null
              ? 'You stole a ${PowerupCopy.nameFor(stolenType)}!'
              : '${PowerupCopy.nameFor(type)} activated!',
        );
      } else {
        final tierTag = upgradeLevel > 0 ? ' (Lvl $upgradeLevel)' : '';
        showOutcomeToast('${PowerupCopy.nameFor(type)}$tierTag activated!');
      }

      if (inlineModalDismissed &&
          !inlineToastAckScheduled &&
          activeImpactReceipt != null) {
        await _acknowledgeActiveImpactReceipt(
          activeImpactReceipt,
          identityToken: token,
        );
      }

      if (!mounted) return;
      _loadProgress();
    } catch (e) {
      if (wasRedeemedFromStash) {
        // A current backend returns a rejected redeemed item to the global
        // stash; an older backend may retain it in the race tray instead. Do
        // not restore our stale local snapshot — re-read both authoritative
        // projections so either server version renders where it actually put
        // the item.
        _loadProgress();
      } else {
        restoreInventory();
      }
      // B3 — map redeem/use rejection codes to friendly copy; unknown/absent
      // codes fall back to the server message (old-backend compat).
      if (mounted) showErrorToast(context, powerupUseErrorCopy(e));
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  Future<void> _acknowledgeActiveImpactReceipt(
    _ActiveImpactReceipt receipt, {
    required String identityToken,
  }) async {
    if (!mounted ||
        receipt.raceId != widget.raceId ||
        identityToken != widget.authService.authToken) {
      return;
    }
    await _api.acknowledgeActiveImpactReceipt(
      identityToken: identityToken,
      raceId: receipt.raceId,
      receiptId: receipt.id,
    );
  }

  Future<List<Map<String, dynamic>>> _loadRacePowerupTargetContext(
    String token,
    String powerupType,
  ) async {
    try {
      final result = await _api.fetchRacePowerupTargetContext(
        identityToken: token,
        raceId: widget.raceId,
        powerupType: powerupType,
      );
      final rawParticipants =
          (result['participants'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .toList(growable: false) ??
          const <Map<String, dynamic>>[];
      final rawPowerupData = result['powerupData'];
      if (rawPowerupData is Map && mounted) {
        setState(() {
          _powerupData = {
            for (final entry in rawPowerupData.entries)
              if (entry.key is String) entry.key as String: entry.value,
          };
        });
      }
      return rawParticipants;
    } catch (_) {
      // Missing/old/malformed/transient typed context keeps the already-loaded
      // progress page exactly as it was. Never replay this URL through the
      // legacy method: older backends already returned that body above.
      return const [];
    }
  }

  /// Optimistic-inventory helper for a confirmed mystery-box open: mirrors
  /// the server's transition on the local projection. The box row keeps its
  /// slot but becomes the rolled HELD powerup; a Fanny Pack that
  /// auto-activated is dropped (server marks it USED).
  void _optimisticallyApplyBoxOpen(
    String powerupId,
    Map<String, dynamic> openResult,
  ) {
    final data = _powerupData;
    final inventory = data?['inventory'] as List?;
    if (data == null || inventory == null || !mounted) return;
    setState(() {
      if (openResult['autoActivated'] == true) {
        data['inventory'] = inventory
            .where((p) => p is Map && p['id'] != powerupId)
            .toList();
      } else {
        data['inventory'] = [
          for (final p in inventory)
            if (p is Map && p['id'] == powerupId)
              <String, dynamic>{
                ...p.cast<String, dynamic>(),
                'type': openResult['type'],
                'rarity': openResult['rarity'],
                'status': 'HELD',
              }
            else
              p,
        ];
      }
    });
  }

  /// Optimistic-inventory helper: drops [powerupId] from the local
  /// `_powerupData['inventory']` projection so its slot empties immediately
  /// instead of lingering until the follow-up _loadProgress() round-trip.
  /// Returns a rollback closure for the failure path (a later successful
  /// _loadProgress() replaces the whole projection anyway).
  VoidCallback _optimisticallyRemoveFromInventory(String powerupId) {
    final data = _powerupData;
    final inventory = data?['inventory'] as List?;
    if (data == null || inventory == null) return () {};
    final saved = List<dynamic>.from(inventory);
    setState(() {
      data['inventory'] = inventory
          .where((p) => p is Map && p['id'] != powerupId)
          .toList();
    });
    return () {
      if (!mounted) return;
      setState(() => data['inventory'] = saved);
    };
  }

  /// Best-effort fetch of the user's global powerup stash. Failures (e.g. an
  /// older backend without the endpoint) leave the stash empty so the redeem UI
  /// simply doesn't appear — never a crash.
  Future<void> _loadGlobalPowerupInventory(String token) async {
    try {
      final result = await _api.fetchPowerupInventory(identityToken: token);
      _applyGlobalPowerupInventory(result);
    } catch (_) {
      if (mounted) {
        setState(() => _globalPowerupInventory = const {});
      }
    }
  }

  void _applyGlobalPowerupInventory(Map<String, dynamic>? envelope) {
    final rawItems = envelope?['items'];
    if (rawItems is! List) return;
    final inventory = <String, int>{};
    for (final raw in rawItems) {
      if (raw is! Map) continue;
      final type = raw['powerupType'];
      final quantity = raw['quantity'];
      if (type is String && quantity is num && quantity.toInt() > 0) {
        inventory[type] = quantity.toInt();
      }
    }
    if (mounted) setState(() => _globalPowerupInventory = inventory);
  }

  /// Spends a globally-owned powerup into this race: redeems it
  /// to a HELD in-race powerup, then immediately runs the normal use flow
  /// (target picker etc.) on it. Reuses [_usePowerup] so targeting/feedback are
  /// identical to box-earned powerups.
  /// [upgradeLevel]/[targetEffectId] carry a choice the caller's confirmation
  /// sheet already made (Pocket Watch's tier + rival effect) straight through
  /// to the use call, so redeeming from the stash lands the same request a HELD
  /// powerup would.
  Future<void> _redeemAndUsePowerup(
    String powerupType, {
    int upgradeLevel = 0,
    String? targetEffectId,
  }) async {
    if (_isActing) return;
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) return;

    // Item 12: the stash row for THIS type is the button that spins.
    _beginAction('stash:$powerupType');
    Map<String, dynamic>? redeemedPowerup;
    try {
      final result = await _api.redeemPowerupToRace(
        identityToken: token,
        raceId: widget.raceId,
        powerupType: powerupType,
      );
      redeemedPowerup =
          (result['result'] as Map<String, dynamic>?)?['powerup']
              as Map<String, dynamic>?;
      // Optimistically reflect the spent stash item.
      final remaining = (_globalPowerupInventory[powerupType] ?? 1) - 1;
      final updated = Map<String, int>.from(_globalPowerupInventory);
      if (remaining > 0) {
        updated[powerupType] = remaining;
      } else {
        updated.remove(powerupType);
      }
      if (mounted) setState(() => _globalPowerupInventory = updated);
    } catch (e) {
      // B3 — the redeem pre-flight can now reject (SIGNAL_JAMMED /
      // RAINSTORM_ACTIVE / NO_ELIGIBLE_TARGETS) BEFORE inventory is spent, so
      // the item stays in the global stash. Friendly copy, server fallback.
      if (mounted) showErrorToast(context, powerupUseErrorCopy(e));
      _endAction();
      return;
    } finally {
      // Release the acting lock before _usePowerup re-acquires it.
      _endAction();
    }

    if (redeemedPowerup == null) {
      // Redeem succeeded but no powerup returned — refresh so it shows in the
      // tray and the user can use it manually.
      _loadProgress();
      return;
    }

    // Run the normal use flow (target picker + use endpoint) on the redeemed
    // HELD powerup.
    await _usePowerup(
      redeemedPowerup,
      upgradeLevel: upgradeLevel,
      targetEffectId: targetEffectId,
    );
  }

  /// Coins a discard is expected to pay, by rarity (batch 2026-08-08, item 1).
  ///
  /// Used ONLY to word the confirmation dialog before the call — the amount
  /// actually credited is whatever the server puts in `coinsAwarded`, which is
  /// what the success toast reports. A stash-redeemed powerup has
  /// `rarity: null` and the backend floors it to the COMMON price, so we show
  /// the same floor here.
  static const Map<String, int> _discardPrices = {
    'COMMON': 2,
    'UNCOMMON': 5,
    'RARE': 10,
  };

  /// The server's live discard prices from `powerupData.discardPrices`
  /// (same shape as `upgradeCosts`: rarity -> coins), or null on a backend
  /// that doesn't send them. Parsed defensively: a non-map, or a map with no
  /// usable numeric entries, reads as absent so we fall back to the bundled
  /// table rather than quoting 0 coins.
  Map<String, int>? get _serverDiscardPrices {
    final raw = _powerupData?['discardPrices'];
    if (raw is! Map) return null;
    final parsed = <String, int>{};
    raw.forEach((key, value) {
      if (key is String && value is num) parsed[key] = value.toInt();
    });
    return parsed.isEmpty ? null : parsed;
  }

  /// Prefers the server's table so prices can be retuned in balance config
  /// without an App Store release; falls back to the bundled 2/5/10 map for an
  /// older backend. Either way this only WORDS the dialog — `coinsAwarded` in
  /// the response is what actually gets credited.
  int _discardPriceFor(Map<String, dynamic> powerup) {
    final table = _serverDiscardPrices ?? _discardPrices;
    // Stash-redeemed powerups have rarity null; the backend floors those to
    // the COMMON price, so quote the same floor.
    final fallback = table['COMMON'] ?? _discardPrices['COMMON']!;
    final rarity = powerup['rarity'];
    if (rarity is! String) return fallback;
    return table[rarity] ?? fallback;
  }

  /// The daily discard-bonus headroom last reported by a DISCARD RESPONSE, or
  /// null if we have never made one this visit. This is the "last write wins"
  /// override over the served value, which can be up to a minute stale.
  int? _discardCapRemaining;

  /// The local date [_discardCapRemaining] was written on. The override must
  /// survive an ordinary progress poll (clearing it there re-introduces the
  /// very bug item 2 fixes, via a memoized server value built before the
  /// discard) but must NOT survive local midnight, when the cap resets.
  String? _discardCapDate;

  /// `powerupData.discardCapRemaining` — additive (batch 2026-08-10b item 2).
  /// Absent on an older backend, and absent whenever the viewer holds nothing
  /// discardable, so it is read defensively and every caller treats null as
  /// "unknown", never as 0.
  int? get _serverDiscardCapRemaining {
    final raw = _powerupData?['discardCapRemaining'];
    return raw is num ? raw.toInt() : null;
  }

  /// The headroom to quote: the discard response's value when we have a fresh
  /// one (it is newer than anything the progress payload can carry), else the
  /// server-served value, else null = unknown.
  int? get _capRemaining {
    final override = _discardCapRemaining;
    if (override != null && _discardCapDate == _todayLocalDate()) {
      return override;
    }
    return _serverDiscardCapRemaining;
  }

  /// What a discard of [powerup] will ACTUALLY pay: the backend awards
  /// `min(price, capRemaining)`. One rule, used by all three price surfaces
  /// (the DISCARD tag, the confirm dialog, and the Pocket Watch sheet).
  int _discardPayoutFor(Map<String, dynamic> powerup) {
    final price = _discardPriceFor(powerup);
    final cap = _capRemaining;
    return cap == null ? price : math.min(price, cap);
  }

  /// Trailing "+N 🪙" price tag for a DISCARD button, in the same shape as the
  /// tier buttons' cost tag. Null (no tag) for an unopened box (pays nothing)
  /// and once the daily discard bonus is exhausted — the confirm dialog spells
  /// out both cases, so the button must not promise coins it won't pay.
  Widget? _discardPriceTrailing(Map<String, dynamic> powerup) {
    final isUnopenedBox = (powerup['status'] as String?) == 'MYSTERY_BOX';
    if (isUnopenedBox || _capRemaining == 0) return null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '+${_discardPayoutFor(powerup)}',
          style: PixelText.pill(size: 12, color: Colors.white),
        ),
        const SizedBox(width: 4),
        const SpinningCoin(size: 14),
      ],
    );
  }

  /// Item 1: discarding is destructive AND now pays coins, so it gets an
  /// explicit confirmation naming the price. Returns true when the user
  /// confirmed. The dialog holds itself open with an in-button spinner while
  /// the request runs (item 12) so a slow network can't be double-tapped.
  Future<void> _confirmAndDiscardPowerup(Map<String, dynamic> powerup) async {
    final isUnopenedBox = (powerup['status'] as String?) == 'MYSTERY_BOX';
    final price = _discardPriceFor(powerup);
    final cap = _capRemaining;
    final capReached = cap == 0;
    final name = PowerupCopy.nameFor(powerup['type'] as String?);

    final String body;
    if (isUnopenedBox) {
      // An unopened box pays nothing — otherwise never opening one would
      // dominate every other play.
      body =
          "Discard this mystery box? You won't get coins for unopened boxes.";
    } else if (capReached) {
      body = "Daily discard bonus reached. You'll get 0 coins.";
    } else if (cap != null && cap < price) {
      // Batch 2026-08-10b item 2: the backend pays min(price, cap), so quoting
      // the full price here promised coins it would not pay.
      body =
          'Discard $name for $cap coins? Your daily discard bonus is nearly '
          'used up.';
    } else {
      // Includes "cap unknown" (older backend): today's exact copy.
      body = 'Discard $name for $price coins?';
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _DiscardConfirmDialog(
        title: isUnopenedBox ? 'DISCARD BOX?' : 'DISCARD?',
        body: body,
      ),
    );

    if (confirmed != true) return;
    await _discardPowerup(powerup);
  }

  Future<void> _discardPowerup(Map<String, dynamic> powerup) async {
    _beginAction(powerup['id'] as String?);
    try {
      final token = widget.authService.authToken;
      if (token == null || token.isEmpty) return;

      final result = await _api.discardPowerup(
        identityToken: token,
        raceId: widget.raceId,
        powerupId: powerup['id'] as String,
      );

      // Item 1 — all three fields are ADDITIVE. A backend that predates them
      // returns none, and we fall back to exactly the old "X discarded" toast.
      final coinsAwarded = result['coinsAwarded'];
      final newBalance = result['coins'];
      final capRemaining = result['capRemaining'];
      if (capRemaining is num) {
        _discardCapRemaining = capRemaining.toInt();
        // Date-stamped so the override survives a stale progress poll but not
        // local midnight (architect R7).
        _discardCapDate = _todayLocalDate();
      }

      // Optimistic coin badge bump. Prefer the server's authoritative balance;
      // fall back to adding the award onto what we hold locally.
      if (newBalance is num) {
        await widget.authService.updateCoins(newBalance.toInt());
      } else if (coinsAwarded is num && coinsAwarded > 0) {
        await widget.authService.updateCoins(
          widget.authService.coins + coinsAwarded.toInt(),
        );
      }

      if (mounted) {
        final name = PowerupCopy.nameFor(powerup['type'] as String?);
        if (coinsAwarded is num && coinsAwarded > 0) {
          showInfoToast(
            context,
            '$name discarded. +${coinsAwarded.toInt()} coins',
          );
        } else {
          // Covers an older backend (no field), an unopened box (always 0) and
          // a user who has hit the daily cap.
          showInfoToast(context, '$name discarded');
        }
        _loadProgress();
      }
    } catch (e) {
      if (mounted) showErrorToast(context, e.toString());
    } finally {
      _endAction();
    }
  }

  /// Resolves the Sneaky Swap target list via the new backend endpoint, which
  /// returns only racers holding a stealable powerup. The returned userIds are
  /// re-joined with [eligibleTargets] (the live participant rows) so the picker
  /// keeps showing avatars/steps. Defends against an older backend that lacks
  /// the endpoint by falling back to the full eligible-racer list.
  Future<List<Map<String, dynamic>>> _resolveSneakySwapTargets(
    String token,
    List<Map<String, dynamic>> eligibleTargets,
  ) async {
    try {
      final result = await _api.fetchSneakySwapTargets(
        identityToken: token,
        raceId: widget.raceId,
      );
      final rawTargets =
          (result['targets'] as List?)?.cast<Map<String, dynamic>>() ??
          const [];

      // Index live participants so we can enrich with steps/avatar.
      final byUserId = <String, Map<String, dynamic>>{
        for (final p in eligibleTargets)
          if (p['userId'] is String) p['userId'] as String: p,
      };

      final resolved = <Map<String, dynamic>>[];
      for (final t in rawTargets) {
        final userId = t['userId'] as String?;
        if (userId == null) continue;
        final live = byUserId[userId];
        resolved.add({
          'userId': userId,
          'displayName': live?['displayName'] ?? t['displayName'] ?? '???',
          if (live?['profilePhotoUrl'] != null)
            'profilePhotoUrl': live!['profilePhotoUrl'],
          if (live?['totalSteps'] != null) 'totalSteps': live!['totalSteps'],
        });
      }
      return resolved;
    } catch (_) {
      // Old backend without the endpoint (404) or transient failure: degrade to
      // the prior behavior of offering every eligible racer.
      return eligibleTargets;
    }
  }

  Future<String?> _showTargetPicker(
    List<Map<String, dynamic>> targets,
    String powerupType,
  ) async {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.of(context).parchment,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      // Cap the sheet so a big race never fills the screen edge-to-edge with
      // names — the list scrolls between a pinned header and footer instead.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.65,
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        PowerupIcon(
                          type: powerupType,
                          size: 22,
                          spinning: true,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          PowerupCopy.nameFor(powerupType),
                          style: PixelText.title(
                            size: 18,
                            color: AppColors.of(context).textDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'CHOOSE A TARGET',
                      style: PixelText.title(
                        size: 12,
                        color: AppColors.of(context).textMid,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      height: 2,
                      color: AppColors.of(context).parchmentDark,
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView.builder(
                  key: const Key('powerup-target-list'),
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  itemCount: targets.length,
                  itemBuilder: (_, i) {
                    final t = targets[i];
                    return GestureDetector(
                      onTap: () {
                        final id = t['userId'] as String?;
                        // Refused (demo, off-script target): keep the sheet
                        // open so the coach's nudge is what answers the tap.
                        if (id != null &&
                            !(widget.demoTargetGate?.call(id) ?? true)) {
                          return;
                        }
                        Navigator.of(ctx).pop(id);
                      },
                      child: Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.of(context).parchmentDark,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            AppAvatar(
                              name: t['displayName'] as String? ?? '???',
                              imageUrl: t['profilePhotoUrl'] as String?,
                              size: 30,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                atName(t['displayName'] as String? ?? '???'),
                                style: PixelText.body(
                                  size: 14,
                                  color: AppColors.of(context).textDark,
                                ),
                              ),
                            ),
                            if (t['totalSteps'] != null)
                              Text(
                                '${_formatSteps((t['totalSteps'] as num).toInt())} steps',
                                style: PixelText.number(
                                  size: 12,
                                  color: AppColors.of(context).textMid,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Column(
                  children: [
                    Container(
                      height: 2,
                      color: AppColors.of(context).parchmentDark,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: PillButton(
                        label: 'CANCEL',
                        variant: PillButtonVariant.secondary,
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<List<String>?> _showQuicksandTargetPicker(
    List<Map<String, dynamic>> targets,
  ) async {
    final selected = <String>[];
    return showModalBottomSheet<List<String>>(
      context: context,
      backgroundColor: AppColors.of(context).parchment,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.72,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
                child: Row(
                  children: [
                    const PowerupIcon(type: 'QUICKSAND', size: 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'CHOOSE UP TO 3 RIVALS',
                        style: PixelText.title(
                          size: 15,
                          color: AppColors.of(context).textDark,
                        ),
                      ),
                    ),
                    Text(
                      '${selected.length}/3',
                      key: const Key('quicksand-target-count'),
                      style: PixelText.title(
                        size: 15,
                        color: AppColors.of(context).accent,
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView.builder(
                  key: const Key('quicksand-target-list'),
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: targets.length,
                  itemBuilder: (_, index) {
                    final target = targets[index];
                    final id = target['userId'] as String?;
                    if (id == null || id.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    final checked = selected.contains(id);
                    final capped = selected.length >= 3 && !checked;
                    return Semantics(
                      selected: checked,
                      button: true,
                      label: target['displayName'] as String? ?? 'Rival',
                      child: CheckboxListTile(
                        value: checked,
                        onChanged: capped
                            ? null
                            : (_) => setSheetState(() {
                                checked
                                    ? selected.remove(id)
                                    : selected.add(id);
                              }),
                        title: Text(
                          target['displayName'] as String? ?? 'Rival',
                          style: PixelText.body(
                            size: 14,
                            color: AppColors.of(context).textDark,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: PillButton(
                        label: 'CANCEL',
                        variant: PillButtonVariant.secondary,
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: PillButton(
                        key: const Key('quicksand-confirm'),
                        label: 'USE QUICKSAND',
                        onPressed: selected.isEmpty
                            ? null
                            : () => Navigator.of(
                                ctx,
                              ).pop(List<String>.unmodifiable(selected)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showQuicksandResults(
    Map<String, dynamic>? result,
    List<Map<String, dynamic>> targets,
  ) async {
    final raw = result?['targetResults'];
    if (raw is! List) {
      showInfoToast(context, 'Quicksand activated!');
      return;
    }
    final names = <String, String>{
      for (final target in targets)
        if (target['userId'] is String)
          target['userId'] as String:
              target['displayName'] as String? ?? 'Rival',
    };
    final rows = raw.whereType<Map>().toList();
    if (rows.isEmpty) {
      showInfoToast(context, 'Quicksand activated!');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: TrailSign(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'QUICKSAND RESULTS',
                style: PixelText.title(
                  size: 17,
                  color: AppColors.of(context).textDark,
                ),
              ),
              const SizedBox(height: 12),
              for (final row in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          names[row['targetUserId']] ?? 'Rival',
                          style: PixelText.body(
                            size: 13,
                            color: AppColors.of(context).textDark,
                          ),
                        ),
                      ),
                      Text(
                        row['outcome'] == 'BLOCKED' ? 'BLOCKED' : 'FROZEN',
                        style: PixelText.title(
                          size: 12,
                          color: row['outcome'] == 'BLOCKED'
                              ? AppColors.of(context).error
                              : AppColors.of(context).accent,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              PillButton(
                label: 'DONE',
                fullWidth: true,
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<String?> _showPineconeDirectionPicker() async {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.of(context).parchment,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PINECONE TARGET',
                  style: PixelText.title(
                    size: 16,
                    color: AppColors.of(context).textMid,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: PillButton(
                        label: 'FRONT',
                        variant: PillButtonVariant.primary,
                        onPressed: () => Navigator.of(ctx).pop('FRONT'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: PillButton(
                        label: 'BEHIND',
                        variant: PillButtonVariant.secondary,
                        onPressed: () => Navigator.of(ctx).pop('BEHIND'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// §6.4 — the Pocket Watch two-mode sheet.
  ///
  /// Targeted mode appears only when the backend advertises
  /// `powerupData.capabilities.pocketWatchTargetEffect`; [PocketWatchSheet]
  /// enforces that internally so an older backend simply shows legacy self mode.
  ///
  /// Shared by both entry points: a HELD Pocket Watch from the tray (which can
  /// also be discarded) and a coin-bought one in the stash (redeemed on
  /// confirm, so there's nothing to discard yet). [onConfirm] carries the
  /// chosen tier + optional rival effect to whichever path opened the sheet.
  void _showPocketWatchSheet({
    required String rarity,
    required List<String>? tierLabels,
    required int myCoins,
    required void Function(int level, String? targetEffectId) onConfirm,
    VoidCallback? onDiscard,
    int? discardPriceCoins,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.of(context).parchment,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      builder: (ctx) {
        return SingleChildScrollView(
          child: PocketWatchSheet(
            powerupData: _powerupData,
            viewerUserId: _myUserId,
            myCoins: myCoins,
            tierLabels:
                tierLabels ??
                PowerupCopy.upgradeTierLabelsFor('POCKET_WATCH') ??
                const ['Extend', 'Extend', 'Extend', 'Extend'],
            costForLevel: (level) =>
                _upgradeCostFor('POCKET_WATCH', rarity, level),
            participants:
                (_progress?['participants'] as List?)
                    ?.cast<Map<String, dynamic>>() ??
                const [],
            onConfirm: (level, targetEffectId) {
              Navigator.of(ctx).pop();
              onConfirm(level, targetEffectId);
            },
            // B5 — parity with the generic sheet: discard is type-agnostic on
            // the backend, so a Pocket Watch can be thrown away too. Matches the
            // generic sheet's behavior: pop, then discard (no extra confirm).
            onDiscard: onDiscard == null
                ? null
                : () {
                    Navigator.of(ctx).pop();
                    onDiscard();
                  },
            discardPriceCoins: discardPriceCoins,
          ),
        );
      },
    );
  }

  /// Confirmation sheet for a coin-bought stash powerup. Parity with
  /// [_showPowerupActions]: same parchment sheet, icon, name and description —
  /// spending a purchased item should never be one unlabelled tap away. No
  /// rarity rule (the stash is type-only, there's no rarity until it's redeemed)
  /// and no DISCARD (you can't throw away something you paid coins for).
  void _showStashPowerupActions(String type, int quantity) {
    final description = PowerupCopy.descriptionFor(type);

    // Pocket Watch is shop-only now, so the stash is its main entry point: it
    // gets the same two-mode sheet a HELD one does. "Extend my buffs" vs
    // "extend ONE debuff I put on a rival" costs coins either way — the choice
    // has to be explicit here too. No DISCARD: nothing is redeemed until the
    // user confirms, so there's nothing to throw away.
    if (type == 'POCKET_WATCH') {
      _showPocketWatchSheet(
        rarity: 'COMMON',
        tierLabels: PowerupCopy.upgradeTierLabelsFor(type),
        myCoins: widget.authService.coins,
        onConfirm: (level, targetEffectId) => _redeemAndUsePowerup(
          type,
          upgradeLevel: level,
          targetEffectId: targetEffectId,
        ),
      );
      return;
    }

    // Owned by the sheet route, not the screen: it must survive the parent
    // rebuilding underneath and die with the sheet.
    var sheetBusy = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.of(context).parchment,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          key: const Key('stash-confirm-sheet'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PowerupIcon(type: type, size: 22, spinning: true),
                        const SizedBox(width: 6),
                        Text(
                          PowerupCopy.nameFor(type),
                          style: PixelText.title(
                            size: 18,
                            color: AppColors.of(context).textDark,
                          ),
                        ),
                      ],
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: CoinBalanceBadge(
                        coins: widget.authService.coins,
                        coinSize: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'FROM YOUR STASH · x$quantity',
                  style: PixelText.body(
                    size: 11,
                    color: AppColors.of(context).textMid,
                  ),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    description,
                    style: PixelText.body(
                      size: 13,
                      color: AppColors.of(context).textMid,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 12),
                // Item 12: this sheet is the ONE action sheet that stays open
                // through its own request. It owns a two-round-trip chain
                // (redeem → use), and popping first would leave the user
                // staring at an unchanged screen for both legs with nothing
                // spinning. StatefulBuilder gives the sheet its own busy flag
                // — the parent screen's setState cannot rebuild a route that
                // is already on top of it.
                StatefulBuilder(
                  builder: (ctx2, setSheetState) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PillButton(
                          key: const Key('stash-confirm-use'),
                          label: 'USE',
                          variant: PillButtonVariant.primary,
                          fontSize: 14,
                          fullWidth: true,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          loading: sheetBusy,
                          onPressed: (_isActing || sheetBusy)
                              ? null
                              : () async {
                                  setSheetState(() => sheetBusy = true);
                                  try {
                                    await _redeemAndUsePowerup(type);
                                  } finally {
                                    // The demo service resolves synchronously,
                                    // so this must clear even on the instant
                                    // path or the tutorial button freezes.
                                    if (ctx2.mounted) {
                                      setSheetState(() => sheetBusy = false);
                                    }
                                  }
                                  if (ctx.mounted) Navigator.of(ctx).pop();
                                },
                        ),
                        const SizedBox(height: 8),
                        PillButton(
                          key: const Key('stash-confirm-cancel'),
                          label: 'CANCEL',
                          variant: PillButtonVariant.secondary,
                          fontSize: 13,
                          fullWidth: true,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 10,
                          ),
                          onPressed: sheetBusy
                              ? null
                              : () => Navigator.of(ctx).pop(),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showPowerupActions(Map<String, dynamic> powerup) {
    final rawType = powerup['type'];
    if (rawType is! String || rawType.trim().isEmpty) return;
    final type = rawType;
    final rawRarity = powerup['rarity'];
    final rarity = rawRarity is String ? rawRarity : 'COMMON';
    final upgradeable = _isUpgradeable(type);
    final tierLabels = PowerupCopy.upgradeTierLabelsFor(type);
    final myCoins = widget.authService.coins;

    // §6.4: Pocket Watch gets its own two-mode sheet. The generic tier sheet
    // can't express "extend all my buffs" vs "extend ONE debuff I put on a
    // rival" — and picking wrong costs coins.
    if (type == 'POCKET_WATCH') {
      _showPocketWatchSheet(
        rarity: rarity,
        tierLabels: tierLabels,
        myCoins: myCoins,
        onConfirm: (level, targetEffectId) => _usePowerup(
          powerup,
          upgradeLevel: level,
          targetEffectId: targetEffectId,
        ),
        onDiscard: () => _confirmAndDiscardPowerup(powerup),
        // Third price surface (ui-test-planner): same _capRemaining and the
        // same min(price, cap) clamp as the DISCARD tag and the dialog, or the
        // sheet keeps promising the full price.
        discardPriceCoins: _capRemaining == 0
            ? null
            : _discardPayoutFor(powerup),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.of(context).parchment,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PowerupIcon(type: type, size: 22, spinning: true),
                        const SizedBox(width: 6),
                        Text(
                          PowerupCopy.nameFor(type),
                          style: PixelText.title(
                            size: 18,
                            color: AppColors.of(context).textDark,
                          ),
                        ),
                      ],
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: CoinBalanceBadge(coins: myCoins, coinSize: 16),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // Rarity is a colour cue only — never a word. The rule under the
                // name carries the same signal the reel frame does.
                Container(
                  width: 44,
                  height: 3,
                  decoration: BoxDecoration(
                    color:
                        _rarityColors[rarity] ?? AppColors.of(context).textMid,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  PowerupCopy.descriptionFor(type),
                  style: PixelText.body(
                    size: 13,
                    color: AppColors.of(context).textMid,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),

                // Tier options for upgradeable powerups; single USE button
                // otherwise. §5.7b: the ladders are disabled in demoMode —
                // every tier above base costs coins.
                if (upgradeable && tierLabels != null && !widget.demoMode)
                  ..._buildTierButtons(
                    ctx,
                    powerup,
                    type,
                    rarity,
                    tierLabels,
                    myCoins,
                  )
                else
                  PillButton(
                    label: 'USE',
                    variant: PillButtonVariant.primary,
                    fontSize: 14,
                    fullWidth: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    onPressed: _isActing
                        ? null
                        : () {
                            Navigator.of(ctx).pop();
                            _usePowerup(powerup);
                          },
                  ),

                // §5.7b: DISCARD is destructive and unrecoverable — throwing
                // away the Protein Shake would dead-end the demo script.
                if (!widget.demoMode) ...[
                  const SizedBox(height: 8),
                  PillButton(
                    label: 'DISCARD',
                    variant: PillButtonVariant.accent,
                    fontSize: 13,
                    fullWidth: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 10,
                    ),
                    trailing: _discardPriceTrailing(powerup),
                    onPressed: _isActing
                        ? null
                        : () {
                            Navigator.of(ctx).pop();
                            _confirmAndDiscardPowerup(powerup);
                          },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  // Upgrade price for a powerup tier. Prefers the backend's live ladders
  // (powerupData.upgradeCosts from getRaceProgress) so the label always shows
  // what the server will actually charge; falls back to the bundled tables
  // when talking to an older backend that doesn't send them.
  int _upgradeCostFor(String? type, String rarity, int level) {
    var byRarity = _upgradeCosts;
    var byType = _upgradeCostsByType;
    final serverCosts = _powerupData?['upgradeCosts'];
    if (serverCosts is Map) {
      final serverByRarity = _parseCostTable(serverCosts['byRarity']);
      if (serverByRarity != null && serverByRarity.isNotEmpty) {
        byRarity = serverByRarity;
        // An empty byType from the server is meaningful ("no overrides"), so
        // it replaces the bundled overrides rather than falling back to them.
        byType = _parseCostTable(serverCosts['byType']) ?? const {};
      }
    }
    final typeTiers = byType[type];
    if (typeTiers != null && level >= 0 && level < typeTiers.length) {
      return typeTiers[level];
    }
    final tiers = byRarity[rarity];
    if (tiers == null || level < 0 || level >= tiers.length) return 0;
    return tiers[level];
  }

  List<Widget> _buildTierButtons(
    BuildContext ctx,
    Map<String, dynamic> powerup,
    String type,
    String rarity,
    List<String> tierLabels,
    int myCoins,
  ) {
    final buttons = <Widget>[];
    for (int level = 0; level <= 3; level++) {
      final cost = _upgradeCostFor(type, rarity, level);
      final affordable = myCoins >= cost;
      final isBase = level == 0;
      final label = isBase
          ? 'USE BASE: ${tierLabels[0]}'
          : 'LVL $level: ${tierLabels[level]}';

      Widget? trailing;
      if (!isBase) {
        trailing = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$cost', style: PixelText.pill(size: 12, color: Colors.white)),
            const SizedBox(width: 4),
            const SpinningCoin(size: 14),
          ],
        );
      }

      buttons.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: PillButton(
            label: label,
            variant: isBase
                ? PillButtonVariant.secondary
                : PillButtonVariant.primary,
            fontSize: 12,
            fullWidth: true,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            trailing: trailing,
            onPressed: (_isActing || !affordable)
                ? null
                : () {
                    Navigator.of(ctx).pop();
                    _usePowerup(powerup, upgradeLevel: level);
                  },
          ),
        ),
      );
    }
    return buttons;
  }

  // Soft drop shadow for light text sitting directly on the checker.
  static const _headerTextShadows = [
    Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  void _scheduleLeaderboardVisibilityCheck() {
    if (_leaderboardVisibilityCheckScheduled || widget.demoMode) {
      return;
    }
    _leaderboardVisibilityCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _leaderboardVisibilityCheckScheduled = false;
      if (!mounted || !_routeVisible || !_appResumed) {
        _leaderboardWasVisible = false;
        return;
      }
      final renderObject = _standingsVisibilityKey.currentContext
          ?.findRenderObject();
      final viewport = _leaderboardViewportKey.currentContext
          ?.findRenderObject();
      if (renderObject is! RenderBox ||
          !renderObject.attached ||
          viewport is! RenderBox ||
          !viewport.attached) {
        _leaderboardWasVisible = false;
        return;
      }
      final top = renderObject.localToGlobal(Offset.zero).dy;
      final bottom = top + renderObject.size.height;
      final viewportTop = viewport.localToGlobal(Offset.zero).dy;
      final viewportBottom = viewportTop + viewport.size.height;
      final visible = bottom > viewportTop && top < viewportBottom;
      if (!visible) {
        _leaderboardWasVisible = false;
        return;
      }
      if (_leaderboardWasVisible) return;
      _leaderboardWasVisible = true;
      unawaited(
        _activationAnalytics.record(
          'race_leaderboard_viewed',
          ownerUserId: widget.authService.userId,
          context: {'race_id': widget.raceId},
        ),
      );
      unawaited(
        _activationAnalytics.flush(
          widget.authService.authToken,
          userId: widget.authService.userId,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Checkered arcade green — the same below-the-fold surface as the tabs,
      // so pushing into a race no longer flips back to the old parchment look.
      body: Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(
              color: AppColors.of(context).roofLight,
              child: CustomPaint(
                painter: ArcadeCheckerPainter(drawBottomStripe: false),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                // Header (fixed, does not scroll) — light chrome on the checker.
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    // Opaque, so scrolled content can't show through the fixed
                    // header (guarded by race_detail_screen_header_test).
                    color: AppColors.of(context).roofLight,
                    border: Border(
                      bottom: BorderSide(
                        color: AppColors.of(context).roofDark,
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(true),
                        child: Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(
                            Icons.arrow_back,
                            color: AppColors.of(context).textLight,
                            size: 24,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          raceDisplayName(
                            _race?['seedKind'] as String?,
                            _race?['name'] as String? ?? 'Race',
                          ),
                          style: PixelText.display(
                            size: 28,
                            color: AppColors.of(context).textLight,
                          ).copyWith(shadows: _headerTextShadows),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_canShareRace())
                        GestureDetector(
                          key: _shareButtonKey,
                          onTap: _sharingRace ? null : _shareRace,
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: _sharingRace
                                ? SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.of(context).textLight,
                                    ),
                                  )
                                : Icon(
                                    Icons.ios_share,
                                    color: AppColors.of(context).textLight,
                                    size: 24,
                                  ),
                          ),
                        ),
                      if (_hasRaceOptions())
                        GestureDetector(
                          onTap: _showRaceOptionsSheet,
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Icon(
                              Icons.more_vert,
                              color: AppColors.of(context).textLight,
                              size: 24,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                Expanded(
                  // Checked before loading/empty: a mid-session prune leaves a
                  // fully-loaded `_race` behind, and a stale link leaves none.
                  // Both land here.
                  child: _notAParticipant
                      ? _buildNotAParticipantState()
                      : _isLoading
                      ? Center(
                          child: CircularProgressIndicator(
                            color: AppColors.of(context).accent,
                          ),
                        )
                      : _race == null
                      ? AppRefreshIndicator(
                          onRefresh: _refreshDetailsFromPull,
                          child: ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(12, 80, 12, 0),
                            children: [
                              // Missing auth can't be fixed by retrying the same
                              // request, so it gets its own copy and no button
                              // that would silently do nothing when tapped.
                              _authMissing
                                  ? const LoadErrorPanel(
                                      icon: Icons.lock_outline,
                                      title: 'Signed out',
                                      message:
                                          'Sign back in to view this race.',
                                    )
                                  : LoadErrorPanel(
                                      title: 'Failed to load race',
                                      message:
                                          _detailsError ?? 'Pull to retry.',
                                      onRetry: () => _loadDetails(),
                                    ),
                            ],
                          ),
                        )
                      : NotificationListener<ScrollNotification>(
                          onNotification: (_) {
                            _scheduleLeaderboardVisibilityCheck();
                            return false;
                          },
                          child: AppRefreshIndicator(
                            onRefresh: _refreshDetailsFromPull,
                            child: SingleChildScrollView(
                              key: _leaderboardViewportKey,
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: EdgeInsets.zero,
                              child: _buildContent(),
                            ),
                          ),
                        ),
                ),
                // Anchored bottom banner, in-flow below the scrollable so it
                // reserves its own space. SafeArea above excludes the bottom, so
                // the slot pads itself clear of the home indicator when an ad is
                // showing; it collapses to zero size otherwise, and also while
                // the keyboard is open so it can't cover the chat composer.
                AdBannerSlot(
                  withBottomSafeArea: true,
                  hideWhenKeyboardOpen: true,
                  // F5/§5.6: no ad is requested or rendered inside the demo.
                  hidden: widget.demoMode,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The one state a 403 deserves. Same parchment game-piece card as every
  /// other board section, so it reads as part of the app rather than an error
  /// screen — and both palettes resolve from the same tokens.
  Widget _buildNotAParticipantState() {
    final colors = AppColors.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Container(
          key: const Key('race-not-a-participant'),
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 22),
          decoration: raceCardDecoration(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.person_off_outlined,
                size: 44,
                color: colors.textMid.withValues(alpha: 0.8),
              ),
              const SizedBox(height: 14),
              Text(
                'You’re not in this race',
                style: PixelText.title(size: 18, color: colors.textDark),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Only runners can open a race board. Find it on Races to join.',
                style: PixelText.body(size: 13, color: colors.textMid),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              PillButton(
                key: const Key('race-not-a-participant-cta'),
                label: 'Find it on Races',
                fullWidth: true,
                padding: PillButton.fullWidthPadding,
                // Pops with `true` so the shell (the only entry point that can
                // be sitting on another tab) swings over to Races. Every other
                // push site is already in the races area, and ignores it.
                onPressed: () => Navigator.of(context).maybePop(true),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    _scheduleLeaderboardVisibilityCheck();
    final status = _race!['status'] as String;

    Widget content;
    bool wrapWithHorizontalPadding = true;

    switch (status) {
      case 'PENDING':
        // Full-bleed race-day hero at the top — padding applied per-section.
        content = _buildPendingContent();
        wrapWithHorizontalPadding = false;
        break;
      case 'ACTIVE':
        final myStatus = _race!['myStatus'] as String? ?? '';
        if (myStatus == 'INVITED') {
          content = _buildInvitedToActiveContent();
          wrapWithHorizontalPadding = false;
        } else {
          // Full-bleed hero; per-child horizontal padding inside.
          content = _buildActiveContent();
          wrapWithHorizontalPadding = false;
        }
        break;
      case 'COMPLETED':
        content = _buildCompletedContent();
        wrapWithHorizontalPadding = false;
        break;
      case 'CANCELLED':
        content = _buildCancelledContent();
        break;
      default:
        return const SizedBox.shrink();
    }

    if (wrapWithHorizontalPadding) {
      content = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: content,
      );
    }
    final showAlerts =
        !widget.demoMode &&
        status == 'ACTIVE' &&
        _race?['myStatus'] == 'ACCEPTED' &&
        widget.authService.onboardingV2Enabled &&
        _alertPermissionUndetermined;
    if (showAlerts) {
      // Item 19 (batch 2026-07-27): the ask is an OVERLAY now — this widget
      // renders nothing and presents itself over the screen after the first
      // frame. It stays mounted here (and only here) so the demo race, which
      // never satisfies `showAlerts`, provably never asks.
      return Column(
        children: [
          RaceAlertOptInCard(
            onEnable: widget.notificationService == null
                ? null
                : () => widget.notificationService!.requestPermission(
                    widget.authService.authToken,
                  ),
          ),
          content,
        ],
      );
    }
    return content;
  }

  // ---------------------------------------------------------------------------
  // Race-day hero: the course scene edge-to-edge with HUD chips floating on
  // the sky — the race itself is the first thing on screen, home-hero style.
  // ---------------------------------------------------------------------------

  Widget _buildRaceHero({
    required List<GoalTrackRunner> runners,
    List<Widget> chips = const [],
    bool showCourse = true,
  }) {
    // A team race drops the course entirely: only two capys ever ran on it (one
    // leader per side), so it cost ~286pt to say less than the scoreboard cards
    // directly below already say. The HUD chips are the part worth keeping, so
    // they re-flow onto the parchment instead of floating on the sky.
    if (!showCourse) {
      if (chips.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < chips.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              chips[i],
            ],
          ],
        ),
      );
    }

    // TR-901: the goal-line/milestone marker is gone with target-steps races;
    // the hero course is purely leader-relative now.
    return Stack(
      children: [
        HomeCourseTrack(
          height: 286,
          backdropAsset: AppThemeAssets.of(context).raceDayCourse,
          frameless: true,
          runners: runners,
        ),
        // HUD chips float over the empty sky band, clear of the bunting and
        // the grandstand. They never intercept the track's own gestures
        // outside their own bounds.
        if (chips.isNotEmpty)
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < chips.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  chips[i],
                ],
              ],
            ),
          ),
      ],
    );
  }

  /// Dark HUD chip floating on the hero sky (same ink language as the
  /// course-track name tags). [onTap] makes it a button.
  Widget _heroChip({Key? key, required Widget child, VoidCallback? onTap}) {
    final chip = Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.of(context).woodDarker.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.18),
          width: 2,
        ),
      ),
      child: child,
    );
    if (onTap == null) return chip;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: chip,
    );
  }

  /// Ticking countdown chip (⏱ 2d 4h 12m). Uses the same 1s ticker as the
  /// rest of the screen via [_countdownNow].
  Widget _countdownChip(DateTime endsAt, {String label = 'ENDS IN'}) {
    final remaining = endsAt.difference(_countdownNow);
    return _heroChip(
      key: widget.tutorialClockKey,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.timer_rounded,
            size: 16,
            color: AppColors.of(context).pillGold,
          ),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: HomeText.label(
                  size: 8,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
              Text(
                _formatCountdownShort(
                  remaining.isNegative ? Duration.zero : remaining,
                ),
                style: PixelText.title(size: 15, color: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // -- Prize pool ----------------------------------------------------------
  //
  // App-funded pools (contract §5.1). `prizePool` is additive: when it is
  // absent — an older backend, or a legacy buy-in race — every read falls back
  // to the buy-in / pot fields and the screen renders exactly as it did before.

  RacePrizePool? get _prizePool => RacePrizePool.fromRace(_race);

  RacePayoutPresentation get _payoutPresentation =>
      RacePayoutPresentation.fromRace(
        _race,
        viewerPlacement: _myViewerPlacement,
        isTeamRace: TeamRace.isTeamRace(_race ?? const {}),
      );

  /// The number shown as the prize. A funded race carries it in `prizePool`;
  /// otherwise the projected pot (which is what the pool re-uses on the wire,
  /// so this is also correct against a newer backend on an old read path).
  int get _prizeCoins =>
      _prizePool?.coins ?? _readInt(_race?['projectedPotCoins'], fallback: 0);

  /// Whether there is any prize contract worth showing: a valid funded pool,
  /// including a truthful zero while it is forming, or a legacy buy-in race.
  bool get _hasPrizeDisplay {
    final pool = _prizePool;
    if (pool != null) return pool.funded || pool.coins > 0;
    return _readInt(_race?['buyInAmount'], fallback: 0) > 0;
  }

  /// A small gold tag: `PROJECTED` while the pool can still move, `MAX` once it
  /// has saturated the ceiling and stops growing.
  Widget _prizeTag(String label, {Key? key}) {
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.of(context).coinDark,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: PixelText.title(size: 8, color: Colors.white)),
    );
  }

  /// Prize-pool chip — tapping opens the payout breakdown sheet.
  Widget _prizeChip() {
    final potCoins = _prizeCoins;
    return _heroChip(
      key: const Key('race-prize-pool-board'),
      onTap: _showPrizePoolSheet,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SpinningCoin(size: 18),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'PRIZE POOL',
                style: HomeText.label(
                  size: 8,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
              Text(
                formatPrizeCoins(potCoins),
                style: PixelText.title(size: 15, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(width: 5),
          Icon(
            Icons.expand_more_rounded,
            size: 16,
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ],
      ),
    );
  }

  void _showPrizePoolSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RacePrizePoolSheet(presentation: _payoutPresentation),
    );
  }

  // Kept temporarily as the compatibility implementation for the older
  // summary helpers below; the shipped path uses the shared sheet above.
  // ignore: unused_element
  void _showLegacyPrizePoolSheet() {
    final potCoins = _prizeCoins;
    final pool = _prizePool;
    final payoutTiers = parsePayoutTiers(_race);
    final isTeamRace = TeamRace.isTeamRace(_race ?? const {});
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.of(context).parchmentLight,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.of(ctx).woodMid,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'PRIZE POOL',
                      style: PixelText.title(
                        size: 16,
                        color: AppColors.of(ctx).textMid,
                      ),
                    ),
                    if (pool != null && pool.projected) ...[
                      const SizedBox(width: 8),
                      _prizeTag(
                        'PROJECTED',
                        key: const Key('race-prize-pool-sheet-projected'),
                      ),
                    ],
                    if (pool != null && pool.atMax) ...[
                      const SizedBox(width: 6),
                      _prizeTag('MAX'),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  formatPrizeCoins(potCoins),
                  style: PixelText.number(
                    size: 40,
                    color: AppColors.of(ctx).coinDark,
                  ),
                ),
                Text(
                  'gold',
                  style: PixelText.body(
                    size: 13,
                    color: AppColors.of(ctx).textMid,
                  ),
                ),
                // Item 8 (batch 2026-07-27): the "Funded by Bara — free to
                // enter" lead-in is gone. What survives is the part that tells
                // the runner something they can act on — that the pool is still
                // moving. A settled pool has nothing left to say, so it says
                // nothing rather than leaving an empty line.
                // One short explainer line. Team races state only the split
                // rule — settlement divides the whole pool evenly across the
                // winning team's non-forfeited runners (backend
                // TR-502/503/504), which is also why the "1ST <full pool>"
                // tier row is suppressed below: it would read as per-runner.
                // Solo races keep the growth note while still projected.
                if ((pool != null && pool.projected) || isTeamRace) ...[
                  const SizedBox(height: 6),
                  Text(
                    key: isTeamRace
                        ? const Key('race-prize-pool-team-split')
                        : null,
                    isTeamRace
                        ? 'The winning team splits the whole pool evenly.'
                        : 'The pool grows as more runners join, and settles '
                              'on who actually walked.',
                    textAlign: TextAlign.center,
                    style: PixelText.body(
                      size: 12,
                      color: AppColors.of(ctx).textMid,
                    ),
                  ),
                ],
                if (!isTeamRace && payoutTiers.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  // An even-split preset (TOP_HALF, ALL_BUT_LAST) can pay 150
                  // identical places on a seeded Daily. Listing them is
                  // useless; four lines that answer "what do I get, and am I
                  // getting it?" are not. Uneven presets keep the podium row.
                  if (_isEvenSplitPayout(payoutTiers))
                    _buildPayoutSummary(
                      payoutTiers,
                      key: const Key('race-prize-pool-payout-summary'),
                      labelColor: AppColors.of(ctx).textMid,
                      amountColor: AppColors.of(ctx).coinDark,
                    )
                  // A graded preset paying a DECAYING curve (a seeded challenge
                  // stamped GEOMETRIC): lead with 1st place, not a per-head
                  // share that no longer exists.
                  else if (_isGradedCurvePayout(payoutTiers))
                    _buildGradedPayoutSummary(
                      payoutTiers,
                      key: const Key('race-prize-pool-graded-payout-summary'),
                      labelColor: AppColors.of(ctx).textMid,
                      amountColor: AppColors.of(ctx).coinDark,
                    )
                  else
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: _buildPayoutBreakdown(
                        payoutTiers,
                        key: const Key('race-prize-pool-summary'),
                        labelColor: AppColors.of(ctx).textMid,
                        amountColor: AppColors.of(ctx).coinDark,
                      ),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  /// Gold-tick light section header on the checker (races/home tab language).
  Widget _checkerSectionHeader(String title, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 16,
            decoration: BoxDecoration(
              color: AppColors.of(context).pillGold,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: AppColors.of(context).pillGoldDark),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: PixelText.display(
                size: 20,
                color: AppColors.of(context).textLight,
              ).copyWith(shadows: _headerTextShadows),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing],
        ],
      ),
    );
  }

  /// Parchment game-piece card for a section body on the checker (home tab
  /// below-the-fold language).
  Widget _sectionCard({
    Key? key,
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(14),
    double horizontalMargin = 12,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalMargin),
      child: Container(
        key: key,
        width: double.infinity,
        padding: padding,
        decoration: raceCardDecoration(context),
        child: child,
      ),
    );
  }

  Widget _buildRaceInfoCard() => RacePayoutScorecard(
    presentation: _payoutPresentation,
    onOpenPayouts: _hasPrizeDisplay ? _showPrizePoolSheet : null,
  );

  // ignore: unused_element
  Widget _buildLegacyRaceInfoCard() {
    final maxDays = _readInt(_race!['maxDurationDays'], fallback: 7);
    final buyInAmount = _readInt(_race!['buyInAmount'], fallback: 0);
    final potCoins = _readInt(_race!['projectedPotCoins'], fallback: 0);
    final payoutTiers = parsePayoutTiers(_race);
    final pool = _prizePool;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: StatColumn(
                label: 'DURATION',
                value: '$maxDays ${maxDays == 1 ? 'DAY' : 'DAYS'}',
                alignment: CrossAxisAlignment.center,
              ),
            ),
            // Funded race (contract §5.1): one honest number, no buy-in.
            if (pool != null && pool.coins > 0)
              Expanded(
                child: Column(
                  key: const Key('race-info-prize-pool'),
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            'PRIZE POOL',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: PixelText.body(
                              size: 11,
                              color: AppColors.of(context).textMid,
                            ),
                          ),
                        ),
                        if (pool.projected) ...[
                          const SizedBox(width: 5),
                          _prizeTag(
                            'PROJECTED',
                            key: const Key('race-prize-pool-projected'),
                          ),
                        ],
                        if (pool.atMax) ...[
                          const SizedBox(width: 5),
                          _prizeTag(
                            'MAX',
                            key: const Key('race-prize-pool-max'),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      pool.formattedCoins,
                      style: PixelText.title(
                        size: 18,
                        color: AppColors.of(context).coinDark,
                      ),
                    ),
                  ],
                ),
              )
            // Legacy buy-in race, or a backend older than this build: exactly
            // the stats this screen has always shown.
            else if (buyInAmount > 0) ...[
              Expanded(
                child: StatColumn(
                  label: 'BUY-IN',
                  value: '$buyInAmount',
                  alignment: CrossAxisAlignment.center,
                  valueColor: AppColors.of(context).coinDark,
                ),
              ),
              Expanded(
                child: StatColumn(
                  label: 'POT',
                  value: '$potCoins',
                  alignment: CrossAxisAlignment.center,
                  valueColor: AppColors.of(context).coinDark,
                ),
              ),
            ],
          ],
        ),
        // Item 8 (batch 2026-07-27): "Funded by Bara — free to enter" is gone.
        // The maxed-out fact is the only part worth a line here, so the line
        // exists only when there is something to say.
        if (pool != null && pool.coins > 0 && pool.atMax) ...[
          const SizedBox(height: 8),
          Text(
            key: const Key('race-prize-pool-funded-copy'),
            'This pool is maxed out.',
            textAlign: TextAlign.center,
            style: PixelText.body(
              size: 11.5,
              color: AppColors.of(context).textMid,
            ),
          ),
        ],
        if (_hasPrizeDisplay && payoutTiers.isNotEmpty) ...[
          const SizedBox(height: 10),
          if (_isEvenSplitPayout(payoutTiers))
            _buildPayoutSummary(
              payoutTiers,
              key: const Key('race-payout-summary'),
            )
          else if (_isGradedCurvePayout(payoutTiers))
            _buildGradedPayoutSummary(
              payoutTiers,
              key: const Key('race-graded-payout-summary'),
            )
          else
            FittedBox(
              fit: BoxFit.scaleDown,
              child: _buildPayoutBreakdown(payoutTiers),
            ),
        ],
      ],
    );
  }

  Widget _buildPendingContent() {
    final isCreator = _race!['isCreator'] as bool? ?? false;
    final myStatus = _race!['myStatus'] as String? ?? '';
    // Seeded daily/weekly races have no creator and auto-start at their scheduled
    // ET midnight — so an opted-in user must see "you're in", not "waiting for the
    // creator to start".
    final isTeamRace = TeamRace.isTeamRace(_race!);
    final participants =
        (_race!['participants'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    // The true field size. `participants` may be one page of it, so the array
    // scan is only the fallback for a backend that doesn't send the summary.
    final acceptedCount =
        _summaryAcceptedCount ??
        participants.where((p) => p['status'] == 'ACCEPTED').length;
    // The rows/sprites actually rendered. Capped independently of the wire:
    // a 473-participant PENDING race built 473 full sprite widgets before this
    // cap, whatever the payload looked like.
    final shownParticipants = participants
        .take(_kParticipantsPageSize)
        .toList(growable: false);
    // "+N more": the remainder of the ROW list the capped view can't show —
    // deliberately counted against every status (not just ACCEPTED), since
    // the rows above render every status. `participantsPagination.total`
    // covers every participant regardless of status; `participants.length`
    // is the same population when paging wasn't honoured. Never negative,
    // and absent entirely when the page already shows everyone.
    final totalParticipantRows =
        (_race?['participantsPagination'] as Map?)?['total'] as int? ??
        participants.length;
    final hiddenParticipantCount =
        totalParticipantRows - shownParticipants.length;

    // 1.1.7: a scheduled race auto-starts at scheduledStartAt; manual start is
    // blocked (and rejected server-side) until then. Read defensively — older
    // payloads omit the field entirely.
    final scheduledStartRaw = _race!['scheduledStartAt'] as String?;
    final scheduledStartAt = scheduledStartRaw != null
        ? DateTime.tryParse(scheduledStartRaw)?.toLocal()
        : null;
    final scheduledInFuture =
        scheduledStartAt != null && scheduledStartAt.isAfter(DateTime.now());

    // Everyone who's in lines up at the start line of the race-day scene.
    final startLineRunners = <GoalTrackRunner>[
      for (final p in shownParticipants)
        if (p['status'] == 'ACCEPTED')
          GoalTrackRunner(
            name: p['displayName'] as String? ?? '???',
            progress: 0,
            isUser: (p['userId'] as String?) == _myUserId,
            profilePhotoUrl: p['profilePhotoUrl'] as String?,
            accessories:
                (p['accessories'] as List?)?.cast<Map<String, dynamic>>() ??
                const [],
            animal: animalFromJson(p['animal']),
          ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildRaceHero(
          runners: startLineRunners,
          chips: [
            if (scheduledInFuture)
              _countdownChip(scheduledStartAt, label: 'STARTS IN')
            else
              _heroChip(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.flag_rounded,
                      size: 16,
                      color: AppColors.of(context).pillGold,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'PENDING',
                      style: PixelText.title(size: 13, color: Colors.white),
                    ),
                  ],
                ),
              ),
            const Spacer(),
            if (_hasPrizeDisplay) _prizeChip(),
          ],
        ),
        if (_postCreateSharePromptVisible && !widget.demoMode) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: RetroCard(
              key: const Key('quick-race-share-prompt'),
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              child: Row(
                children: [
                  Icon(
                    Icons.ios_share_rounded,
                    color: AppColors.of(context).pillGreenDark,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Bring in the second walker. This race starts automatically when they join.',
                      style: PixelText.body(
                        size: 12.5,
                        color: AppColors.of(context).textDark,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Dismiss',
                    onPressed: () =>
                        setState(() => _postCreateSharePromptVisible = false),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),

        // SPECTATING indicator (+ JOIN CTA in public preview) — the ACTIVE
        // board carries the same banner; a PENDING race needs it too, since a
        // not-yet-started public race is the commonest thing to preview.
        if (_isSpectator) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
            child: _buildSpectatorBanner(),
          ),
          const SizedBox(height: 16),
        ],

        _checkerSectionHeader('RACE DETAILS'),
        _sectionCard(
          padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
          child: _buildRaceInfoCard(),
        ),
        if (!widget.demoMode && myStatus == 'INVITED') ...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _buildInviteDecisionRow(),
          ),
        ],
        const SizedBox(height: 16),

        if (isTeamRace) ...[
          // TR-802: the LoL-style lobby replaces the flat participants list.
          _checkerSectionHeader('TEAM LOBBY'),
          _sectionCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TeamLobbyBoard(
                  race: _race!,
                  participants: participants,
                  myUserId: _myUserId,
                  // A spectator/preview viewer sees the team split read-only:
                  // picking a side happens inside the JOIN flow's team-side
                  // picker, never by tapping a peg they have no row for.
                  onTapEmptySlot:
                      (_isActing || _isSpectator || myStatus == 'DECLINED')
                      ? null
                      : _onLobbySlotTap,
                ),
                if (myStatus == 'INVITED' && _bothSidesFull()) ...[
                  // TR-207: over-inviting is allowed and the first to accept
                  // get in. A surplus invitee keeps their invite — it just
                  // can't be accepted until someone leaves (TR-205).
                  const SizedBox(height: 12),
                  Container(
                    key: const Key('team-lobby-race-full'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.of(context).parchmentDark,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.of(context).parchmentBorder,
                        width: 2,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.hourglass_top_rounded,
                          size: 18,
                          color: AppColors.of(
                            context,
                          ).textMid.withValues(alpha: 0.8),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Both teams are full. Someone beat you to it! '
                            'Your invite stays put: if a spot frees up, hop '
                            'straight in.',
                            style: PixelText.body(
                              size: 12.5,
                              color: AppColors.of(context).textMid,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (myStatus == 'ACCEPTED') ...[
                  const SizedBox(height: 12),
                  Text(
                    'Tap an empty peg on the other side to switch teams',
                    textAlign: TextAlign.center,
                    style: PixelText.body(
                      size: 12,
                      color: AppColors.of(context).textMid,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ] else ...[
          _checkerSectionHeader(
            'PARTICIPANTS',
            trailing: Pill(
              label: '$acceptedCount',
              background: AppColors.of(context).parchmentDark,
              foreground: AppColors.of(context).textMid,
              fontSize: 12,
            ),
          ),
          _sectionCard(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final p in shownParticipants) _buildParticipantRow(p),
                // The header Pill shows the true total; without this row the
                // list below it would silently disagree with no affordance
                // explaining the gap.
                if (hiddenParticipantCount > 0)
                  Padding(
                    key: const Key('participants-more-row'),
                    padding: const EdgeInsets.only(bottom: 8, top: 2),
                    child: Text(
                      '+$hiddenParticipantCount more',
                      style: PixelText.body(
                        size: 14,
                        color: AppColors.of(context).textMid,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: _buildPendingActions(
            isCreator: isCreator,
            myStatus: myStatus,
            acceptedCount: acceptedCount,
            scheduledInFuture: scheduledInFuture,
            scheduledStartAt: scheduledStartAt,
          ),
        ),
        if (_canLeaveLegacyTeamLobby) ...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: PillButton(
              label: 'LEAVE LOBBY',
              variant: PillButtonVariant.accent,
              fontSize: 13,
              fullWidth: true,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              onPressed: _isActing ? null : _leaveTeamLobby,
            ),
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildPendingActions({
    required bool isCreator,
    required String myStatus,
    required int acceptedCount,
    required bool scheduledInFuture,
    required DateTime? scheduledStartAt,
  }) {
    // TR-301 gating for team races: both sides equal and nonzero. The lever
    // stays visibly disabled with live "Teams must be even — 2v1" copy.
    final isTeamRace = TeamRace.isTeamRace(_race ?? const {});
    // Summary counts first — scanning a paged `participants` array would show
    // "Teams must be even — 1v0" on a full 2v2 lobby and disarm the lever.
    final (teamACount, teamBCount) = _teamAcceptedCounts();
    final teamsEvenAndReady = teamACount == teamBCount && teamACount > 0;
    final startBlocked = isTeamRace ? !teamsEvenAndReady : acceptedCount < 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // TR-304: a scheduled team race whose start time has passed while the
        // teams are uneven — the cron skipped it and keeps retrying, so the
        // race just sits PENDING. Say so, or the elapsed countdown reads as a
        // bug.
        if (isTeamRace &&
            scheduledStartAt != null &&
            !scheduledInFuture &&
            !teamsEvenAndReady) ...[
          RetroCard(
            key: const Key('team-scheduled-uneven-banner'),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: Row(
              children: [
                Icon(
                  Icons.pause_circle_filled_rounded,
                  size: 18,
                  color: AppColors.of(context).error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'START PAUSED. WAITING FOR EVEN TEAMS',
                        style: PixelText.title(
                          size: 12,
                          color: AppColors.of(context).textDark,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        teamACount == 0 || teamBCount == 0
                            ? "Both teams need at least 1 racer. We'll start "
                                  'it automatically as soon as they even up.'
                            : "It's ${teamACount}v$teamBCount right now. "
                                  "We'll start it automatically as soon as "
                                  'the teams are even.',
                        style: PixelText.body(
                          size: 12,
                          color: AppColors.of(context).textMid,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // 1.1.7: scheduled auto-start banner, shown to every viewer of a
        // PENDING race that has a future scheduledStartAt. Live countdown,
        // driven by the same 1s ticker the active-race countdown uses.
        if (scheduledInFuture && scheduledStartAt != null) ...[
          RetroCard(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: Row(
              children: [
                Icon(
                  Icons.schedule,
                  size: 18,
                  color: AppColors.of(context).pillGreenDark,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Countdown lives in the hero's STARTS IN chip — the
                      // banner carries the absolute local time.
                      Text(
                        'AUTO-START SCHEDULED',
                        style: PixelText.title(
                          size: 14,
                          color: AppColors.of(context).textDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'at ${_formatScheduledStart(scheduledStartAt)}',
                        style: PixelText.body(
                          size: 12,
                          color: AppColors.of(context).textMid,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Actions. A spectator/preview viewer owns none of them — the
        // "waiting for another walker / share your race" card is the creator's
        // status, not a bystander's.
        if (_isSpectator) ...[
          const SizedBox.shrink(),
        ] else if (!widget.demoMode &&
            isAutomaticStartRace(_race ?? const {})) ...[
          RetroCard(
            key: const Key('quick-race-auto-start-pending'),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'WAITING FOR ANOTHER WALKER',
                  style: PixelText.title(
                    size: 14,
                    color: AppColors.of(context).textDark,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Share your race, or wait for someone to find it. It starts automatically when one more person joins.',
                  style: PixelText.body(
                    size: 12.5,
                    color: AppColors.of(context).textMid,
                  ),
                ),
                if (_canShareRace()) ...[
                  const SizedBox(height: 12),
                  PillButton(
                    key: const Key('quick-race-inline-share'),
                    label: _sharingRace ? 'SHARING…' : 'SHARE',
                    icon: Icons.ios_share_rounded,
                    variant: PillButtonVariant.secondary,
                    fullWidth: true,
                    onPressed: _sharingRace ? null : _shareRace,
                  ),
                ],
              ],
            ),
          ),
        ] else if (isCreator) ...[
          if (!scheduledInFuture) ...[
            RetroCard(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              child: Row(
                children: [
                  Icon(
                    Icons.groups_rounded,
                    size: 18,
                    color: AppColors.of(context).pillGreenDark,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This race is waiting to start. Invite friends, and once '
                      '2+ have joined, tap Start Race. It won’t begin on its own.',
                      style: PixelText.body(
                        size: 13,
                        color: AppColors.of(context).textDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          PillButton(
            label: 'INVITE FRIENDS',
            variant: PillButtonVariant.secondary,
            fontSize: 14,
            fullWidth: true,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            onPressed: _isActing ? null : _inviteMore,
          ),
          const SizedBox(height: 10),
          _StartLeverPulse(
            armed: !scheduledInFuture && !_isActing && !startBlocked,
            child: PillButton(
              label: scheduledInFuture
                  ? 'AUTO-START SCHEDULED'
                  : (_isActing ? 'STARTING...' : 'START RACE'),
              variant: PillButtonVariant.primary,
              fontSize: 14,
              fullWidth: true,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              onPressed: (scheduledInFuture || _isActing || startBlocked)
                  ? null
                  : _startRace,
            ),
          ),
          if (!scheduledInFuture && startBlocked) ...[
            const SizedBox(height: 6),
            Text(
              isTeamRace
                  ? (teamACount == 0 && teamBCount == 0
                        ? 'Both teams need at least 1 racer'
                        : 'Teams must be even. ${teamACount}v$teamBCount')
                  : 'Need at least 2 participants to start',
              style: PixelText.body(
                size: 12,
                color: AppColors.of(context).textLight.withValues(alpha: 0.9),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ] else if (myStatus == 'INVITED') ...[
          // The decision row lives immediately under Race Details.
        ],
      ],
    );
  }

  Widget _buildInvitedToActiveContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        _checkerSectionHeader('RACE DETAILS'),
        _sectionCard(
          padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
          child: _buildRaceInfoCard(),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: _buildInviteDecisionRow(),
        ),
        const SizedBox(height: 16),
        _sectionCard(
          child: Column(
            children: [
              Icon(
                Icons.directions_run_rounded,
                size: 32,
                color: AppColors.of(context).accent,
              ),
              const SizedBox(height: 8),
              Text(
                'This race is already underway!',
                style: PixelText.title(
                  size: 16,
                  color: AppColors.of(context).textDark,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                'Join now and your steps will count from when you accept.',
                style: PixelText.body(
                  size: 14,
                  color: AppColors.of(context).textMid,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildInviteDecisionRow() {
    final buyIn = _prizePool == null
        ? _readInt(_race?['buyInAmount'], fallback: 0)
        : 0;
    final acceptLabel = _isActing && _acceptingInvite == true
        ? 'JOINING…'
        : buyIn > 0
        ? 'ACCEPT · $buyIn'
        : 'ACCEPT';
    final declineLabel = _isActing && _acceptingInvite == false
        ? 'DECLINING…'
        : 'DECLINE';
    return SizedBox(
      key: const Key('race-invite-actions'),
      height: 52,
      child: Row(
        children: [
          Expanded(
            child: PillButton(
              key: const Key('race-invite-accept'),
              label: acceptLabel,
              leading: buyIn > 0 ? const SpinningCoin(size: 15) : null,
              variant: PillButtonVariant.decision,
              fontSize: 13,
              fullWidth: true,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              loading: _isActing && _acceptingInvite == true,
              onPressed: _isActing ? null : () => _respondToInvite(true),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: PillButton(
              key: const Key('race-invite-decline'),
              label: declineLabel,
              variant: PillButtonVariant.destructive,
              fontSize: 13,
              fullWidth: true,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              loading: _isActing && _acceptingInvite == false,
              onPressed: _isActing ? null : () => _respondToInvite(false),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveContent() {
    // TR-901: target-steps races are gone — `targetSteps` may still arrive on
    // the wire from the backend (compat, TR-903) but is deliberately ignored.
    final finishReward = _race!['finishReward'] as Map<String, dynamic>?;
    final finishRewardPool = finishReward != null
        ? _readInt(finishReward['pool'], fallback: 0)
        : 0;
    final finishRewardPlaces = finishReward != null
        ? _readInt(finishReward['paidPlaces'], fallback: 0)
        : 0;
    final endsAtRaw = _race!['endsAt'] as String?;
    final endsAt = endsAtRaw != null
        ? DateTime.tryParse(endsAtRaw)?.toLocal()
        : null;

    final chips = <Widget>[
      if (endsAt != null) _countdownChip(endsAt),
      const Spacer(),
      if (_hasPrizeDisplay) _prizeChip(),
    ];

    if (_progressState.shouldShowInitialLoading) {
      return Column(
        children: [
          _buildRaceHero(runners: const [], chips: chips),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: KeyedSubtree(
              key: Key('race-detail-progress-skeleton'),
              child: _RaceProgressSkeleton(),
            ),
          ),
        ],
      );
    }

    if (_progressState.isError && !_progressState.hasData) {
      return Column(
        children: [
          _buildRaceHero(runners: const [], chips: chips),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: KeyedSubtree(
              key: const Key('race-detail-progress-error'),
              child: LoadErrorPanel(
                title: 'Couldn’t load race progress',
                message: 'Check your connection and try again.',
                onRetry: _loadProgress,
              ),
            ),
          ),
        ],
      );
    }

    final progress = _progressState.data ?? _progress ?? const {};
    // F-12e — prefer the server's placement (contract §5 C1) so home, the
    // races list and this screen agree on one rank. The client comparator
    // remains the fallback for an older backend that omits the field.
    final participants = orderRaceParticipantsForDisplay(
      (progress['participants'] as List?)?.cast<Map<String, dynamic>>() ?? [],
    );
    final isTeamRace = TeamRace.isTeamRace(_race!);

    // Position runners against the expected-pace denominator (leader-capped)
    // so time-based races show sane positions from minute one — see
    // _courseDenominator.
    final leaderSteps = _leaderSteps(participants);
    final courseDenominator = _courseDenominator(leaderSteps);

    final raceTargetTextColor = AppColors.of(context).isDark
        ? AppColors.of(context).textLight
        : AppColors.of(context).pillGold;

    return Column(
      children: [
        // THE RACE — full-bleed race-day hero with HUD chips on the sky.
        // A team race drops the course (see _buildRaceHero) — the scoreboard
        // cards below carry the head-to-head. Only the HUD chips remain.
        //
        // NOTE: this retires the TR-804 team glow/pennant chrome on course
        // capys. Its only producer was this runner list, and the PENDING and
        // COMPLETED heroes never set `teamColor`, so nothing else rendered it.
        if (isTeamRace)
          _buildRaceHero(chips: chips, runners: const [], showCourse: false)
        else
          _buildRaceHero(
            chips: chips,
            runners: [
              for (final p in participants)
                GoalTrackRunner(
                  name: p['stealthed'] == true
                      ? '???'
                      : (p['displayName'] as String? ?? '???'),
                  progress: p['stealthed'] == true
                      ? _jitterProgress(p['userId'] as String? ?? '')
                      : _courseProgress(p['totalSteps'], courseDenominator),
                  isUser: (p['userId'] as String?) == _myUserId,
                  isStealthed: p['stealthed'] == true,
                  profilePhotoUrl: p['profilePhotoUrl'] as String?,
                  accessories:
                      (p['accessories'] as List?)
                          ?.cast<Map<String, dynamic>>() ??
                      const [],
                  animal: p['stealthed'] == true
                      ? null
                      : animalFromJson(p['animal']),
                ),
            ],
          ),

        if (_progressState.isRefreshing)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: LinearProgressIndicator(
              minHeight: 2,
              color: AppColors.of(context).accent,
              backgroundColor: Colors.transparent,
            ),
          ),

        // TOURNAMENT MATCHUP banner — a tappable link back to the bracket,
        // shown only when this race is a tournament matchup (additive fields,
        // absent on non-matchup / older responses; read defensively, spec §9).
        if (_buildTournamentBanner() case final banner?)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: banner,
          ),

        // SPECTATING indicator — shown when the viewer isn't one of the race's
        // racers (e.g. a tournament participant watching another matchup). The
        // race renders read-only; this makes that explicit.
        if (_isSpectator)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: _buildSpectatorBanner(),
          ),

        // GLOBAL STEP EVENT — "2x STEPS" banner with a countdown, shown only
        // while an event window is active. Absent for old responses.
        if (_buildGlobalEventBanner() case final banner?)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: banner,
          ),

        if (finishRewardPool > 0 || endsAt == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                key: const Key('race-target-header'),
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (endsAt == null)
                    Text(
                      'RACE IN PROGRESS',
                      textAlign: TextAlign.center,
                      style: PixelText.title(
                        size: 16,
                        color: raceTargetTextColor,
                      ).copyWith(shadows: _headerTextShadows),
                    ),
                  if (finishRewardPool > 0) ...[
                    const SizedBox(height: 2),
                    Text(
                      key: const Key('race-finish-reward-copy'),
                      finishRewardPlaces == 1
                          ? 'Winner takes $finishRewardPool gold'
                          : finishRewardPlaces > 1
                          ? 'Top $finishRewardPlaces split $finishRewardPool gold'
                          : 'Top finishers split $finishRewardPool gold',
                      textAlign: TextAlign.center,
                      style: PixelText.body(
                        size: 13,
                        color: raceTargetTextColor,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        const SizedBox(height: 18),

        // POWERUPS — slots, stash, and active effects on one card. Hidden for
        // a spectator (they hold no powerups and can take no actions here).
        if (!_isSpectator) ...[
          StaggerIn(
            index: 0,
            child: Column(
              children: [
                _checkerSectionHeader(
                  'POWERUPS',
                  trailing: _powerupsHeaderTrailing(),
                ),
                _sectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_powerupData != null &&
                          _powerupData!['enabled'] == true) ...[
                        // §3.2 — the "X steps to go" helper sits ABOVE the
                        // box/item slots so the earn-progress reads before the
                        // slots it fills.
                        if (_buildNextPowerupHelper() case final helper?)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: helper,
                          ),
                        _buildInventoryContent(),
                      ] else
                        Row(
                          children: [
                            Icon(
                              Icons.block_rounded,
                              size: 18,
                              color: AppColors.of(
                                context,
                              ).textMid.withValues(alpha: 0.5),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Powerups are disabled for this race',
                                style: PixelText.body(
                                  size: 14,
                                  color: AppColors.of(context).textMid,
                                ),
                              ),
                            ),
                          ],
                        ),
                      _buildActiveEffectsSection(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
        ],

        // SCOREBOARD (team) — honest combined totals + lead on top, then the
        // two rosters as color-matched columns beneath their plaques. Totals
        // come from the backend team block (always honest, TR-658), falling
        // back to summing visible planks on older payloads. Solo races keep the
        // single STANDINGS list. This sits below the actionable POWERUPS card.
        StaggerIn(
          key: _standingsVisibilityKey,
          index: 1,
          child: Column(
            children: [
              _checkerSectionHeader(isTeamRace ? 'SCOREBOARD' : 'STANDINGS'),
              _sectionCard(
                key: isTeamRace
                    ? const ValueKey('team-scoreboard-shell')
                    : null,
                horizontalMargin: isTeamRace ? 6 : 12,
                padding: const EdgeInsets.all(8),
                child: isTeamRace
                    ? Builder(
                        builder: (context) {
                          // One totals source for the cards, the LEADING ribbon
                          // AND the lead banner. Deriving the ribbon from
                          // TeamRace.leadingTeam instead would recompute off
                          // the participants list, which coerces a stealthed
                          // member's null steps to 0 — the crown could then
                          // land on the card showing the SMALLER number.
                          final totalA = _teamTotalFromProgress(
                            progress,
                            participants,
                            RaceTeam.teamA,
                          );
                          final totalB = _teamTotalFromProgress(
                            progress,
                            participants,
                            RaceTeam.teamB,
                          );
                          final nameA = TeamRace.teamName(
                            _race!,
                            RaceTeam.teamA,
                          );
                          final nameB = TeamRace.teamName(
                            _race!,
                            RaceTeam.teamB,
                          );
                          return Column(
                            children: [
                              TeamVsChips(teamAName: nameA, teamBName: nameB),
                              const SizedBox(height: 12),
                              TeamScoreboardCards(
                                teamAName: nameA,
                                teamBName: nameB,
                                teamATotal: totalA,
                                teamBTotal: totalB,
                                teamALeader: TeamCardMember.topScorerOf(
                                  participants,
                                  RaceTeam.teamA,
                                ),
                                teamBLeader: TeamCardMember.topScorerOf(
                                  participants,
                                  RaceTeam.teamB,
                                ),
                              ),
                              const SizedBox(height: 14),
                              TeamLeadBanner(
                                teamAName: nameA,
                                teamBName: nameB,
                                teamATotal: totalA,
                                teamBTotal: totalB,
                                myTeam: _myTeam(participants),
                              ),
                            ],
                          );
                        },
                      )
                    : _standingsList(
                        participants,
                        hasMore: _participantsHasMore,
                        isLoadingMore: _participantsLoadingMore,
                      ),
              ),
              if (isTeamRace) ...[
                const SizedBox(height: 18),
                _checkerSectionHeader('STANDINGS'),
                _sectionCard(
                  key: const ValueKey('team-standings-shell'),
                  horizontalMargin: 6,
                  padding: const EdgeInsets.all(8),
                  child: Builder(
                    builder: (context) {
                      final totalA = _teamTotalFromProgress(
                        progress,
                        participants,
                        RaceTeam.teamA,
                      );
                      final totalB = _teamTotalFromProgress(
                        progress,
                        participants,
                        RaceTeam.teamB,
                      );
                      return _buildTeamTwoColumns(
                        participants,
                        teamLaneStatesForTotals(totalA, totalB),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),

        // ACTIVITY & CHAT
        StaggerIn(index: 2, child: _buildActivityTabsSection()),

        if (_canForfeitLegacyTeamRace(participants)) ...[
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: PillButton(
              label: 'FORFEIT',
              variant: PillButtonVariant.accent,
              fontSize: 13,
              fullWidth: true,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              onPressed: _isActing ? null : _forfeitTeamRace,
            ),
          ),
        ],

        const SizedBox(height: 24),
      ],
    );
  }

  /// `forfeitedAt` is additive, so a missing value on an older payload means
  /// the member remains eligible for the legacy control.
  bool _iHaveForfeited(List<Map<String, dynamic>> participants) {
    for (final participant in participants) {
      if (participant['userId'] == _myUserId) {
        return TeamRace.hasForfeited(participant);
      }
    }
    return false;
  }

  // "2x STEPS — ends in mm:ss" banner for an active global step-multiplier
  // event. Returns null when there is no active event (or the response omitted
  // the field, e.g. an older backend), or once the countdown has elapsed.
  /// Tappable banner linking a tournament matchup race back to its bracket.
  /// Reads the additive `tournamentId` / `tournamentRoundLabel` / `tournamentName`
  /// fields defensively — absent on non-matchup or older responses → no banner
  /// (spec §6.3/§9). Null-safe throughout: a missing label degrades to a plain
  /// "TOURNAMENT MATCHUP" line rather than crashing.
  /// True when the signed-in viewer is NOT one of this race's racers — i.e.
  /// they're spectating (a tournament participant watching another matchup, per
  /// the relaxed race-view auth). Read defensively: only true once participants
  /// are loaded and the viewer isn't among them, so a mid-load frame never
  /// flashes "spectating".
  bool get _isSpectator {
    final race = _race;
    if (race == null) return false;
    // Once the server has honoured our paging capability, absence from the
    // (possibly truncated) array proves nothing — a real racer's own row
    // routinely falls outside it. `myStatus` comes from the backend's
    // dedicated (raceId, userId) lookup and is the only trustworthy
    // membership signal once paging is in play.
    if (_serverHonouredParticipantsPaging) return _myParticipantStatus == null;
    // Unpaged payload: keep the established array test verbatim. It is
    // deliberately stricter than `myStatus` — a differently-versioned backend
    // must not be able to hand a spectator a composer whose posts would 403.
    final participants = (race['participants'] as List?)
        ?.whereType<Map>()
        .toList();
    if (participants == null || participants.isEmpty) return false;
    return !participants.any((p) => p['userId'] == _myUserId);
  }

  /// A non-participant previewing a PUBLIC, NON-TOURNAMENT race served by the
  /// backend's `race_preview` carve-out. Deliberately NOT a second state
  /// alongside `_isSpectator`: it is `_isSpectator` plus the discriminator the
  /// backend predicate itself uses, mirroring `_canShowCreatorOptions` /
  /// `_stampedLeaveAction`'s existing guard shape in this file.
  ///
  /// `myStatus == null` alone is NOT usable here — a tournament-bracket
  /// spectator reads null too, and offering them a JOIN would 400
  /// (`TOURNAMENT_RACE_LOCKED`).
  bool get _isPreviewViewer {
    final race = _race;
    if (widget.demoMode || race == null) return false;
    if (!_isSpectator) return false;
    return race['tournamentId'] == null && race['isPublic'] == true;
  }

  /// The preview viewer can actually join right now. Read defensively: an
  /// unknown/absent status is treated as not joinable.
  bool get _canJoinFromPreview {
    if (!_isPreviewViewer) return false;
    final status = _race?['status'] as String? ?? '';
    return status == 'PENDING' || status == 'ACTIVE';
  }

  /// Joins the previewed race through the SHARED discovery join flow — the same
  /// buy-in confirmation and team-side picker the public-races list and home
  /// cards use. No new dialog is introduced here.
  Future<void> _joinFromPreview() async {
    final race = _race;
    if (race == null || _joiningFromPreview || !_canJoinFromPreview) return;
    setState(() => _joiningFromPreview = true);
    try {
      final result = await DiscoveryJoinCoordinator(
        authService: widget.authService,
        backendApiService: _api,
      ).joinRace(context, race);
      if (result == null || !mounted) return;
      // Re-read as a participant: the reload takes the normal path, which is
      // what arms polling, the feed and the chat for the first time.
      await _loadDetails();
    } finally {
      if (mounted) setState(() => _joiningFromPreview = false);
    }
  }

  Widget _buildSpectatorBanner() {
    final canJoin = _canJoinFromPreview;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.of(context).woodDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.of(context).roofEdge, width: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.visibility_rounded,
                size: 16,
                color: Colors.white.withValues(alpha: 0.9),
              ),
              const SizedBox(width: 8),
              Text(
                'SPECTATING · READ-ONLY',
                style: PixelText.title(
                  size: 12,
                  color: Colors.white.withValues(alpha: 0.92),
                ),
              ),
            ],
          ),
          // Public, non-tournament races get the way in. Tournament matchups
          // never do — that JOIN would be rejected server-side.
          if (canJoin) ...[
            const SizedBox(height: 4),
            Text(
              'You’re not in this one yet.',
              textAlign: TextAlign.center,
              style: PixelText.body(
                size: 11.5,
                color: Colors.white.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(height: 9),
            PillButton(
              key: const Key('race-preview-join-cta'),
              label: _joiningFromPreview ? 'JOINING…' : 'JOIN THIS RACE',
              variant: PillButtonVariant.accent,
              fontSize: 13,
              fullWidth: true,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 11),
              onPressed: _joiningFromPreview ? null : _joinFromPreview,
            ),
          ],
        ],
      ),
    );
  }

  Widget? _buildTournamentBanner() {
    final race = _race;
    if (race == null) return null;
    final tournamentId = race['tournamentId'];
    if (tournamentId is! String || tournamentId.isEmpty) return null;

    final rawLabel = race['tournamentRoundLabel'];
    final label = (rawLabel is String && rawLabel.trim().isNotEmpty)
        ? rawLabel.trim().toUpperCase()
        : 'MATCHUP';
    final rawName = race['tournamentName'];
    final name = (rawName is String && rawName.trim().isNotEmpty)
        ? rawName.trim()
        : 'Tournament';

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TournamentDetailScreen(
              authService: widget.authService,
              tournamentId: tournamentId,
              backendApiService: widget.backendApiService,
              friends: widget.friends,
            ),
          ),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              AppColors.of(context).pillGold,
              AppColors.of(context).pillGoldDark,
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.of(context).pillGoldShadow,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$label: ${name.toUpperCase()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PixelText.title(
                      size: 12,
                      color: AppColors.of(context).textDark,
                    ),
                  ),
                  Text(
                    'Tap to see the bracket',
                    style: PixelText.body(
                      size: 11,
                      color: AppColors.of(context).textDark,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: AppColors.of(context).textDark,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Widget? _buildGlobalEventBanner() {
    final event = _globalEvent;
    if (event == null) return null;
    if (event['active'] != true) return null;

    final endsAtRaw = event['endsAt'];
    final endsAt = endsAtRaw is String
        ? DateTime.tryParse(endsAtRaw)?.toLocal()
        : null;
    if (endsAt == null) return null;

    final remaining = endsAt.difference(_countdownNow);
    if (remaining.isNegative || remaining == Duration.zero) return null;

    final multiplierRaw = event['multiplier'];
    if (multiplierRaw is! num || !multiplierRaw.isFinite) return null;
    final multiplier = multiplierRaw.toInt();

    // Shared, self-ticking banner — same look on the race page and home screen.
    return GlobalEventBanner(
      key: const Key('race-global-event-banner'),
      multiplier: multiplier,
      endsAt: endsAt,
    );
  }

  Widget? _buildNextPowerupHelper() {
    final powerupStepInterval = _readNullableInt(
      _powerupData?['powerupStepInterval'],
    );
    final stepsUntilNextPowerup = _readNullableInt(
      _powerupData?['stepsUntilNextPowerup'],
    );

    if (powerupStepInterval == null ||
        powerupStepInterval <= 0 ||
        stepsUntilNextPowerup == null ||
        stepsUntilNextPowerup <= 0) {
      return null;
    }

    return Text(
      'You earn a powerup every ${_formatSteps(powerupStepInterval)} steps. ${_formatSteps(stepsUntilNextPowerup)} to go.',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: PixelText.body(size: 13, color: AppColors.of(context).textMid),
    );
  }

  List<Map<String, dynamic>> get _normalizedPowerupInventory =>
      normalizePowerupInventory(_powerupData?['inventory']);

  /// Slot mystery boxes the user can open right now. IDs are validated before
  /// they can reach the opening route, which also keeps malformed old/new
  /// payloads from producing a misleading alert or Open All affordance.
  List<String> get _openableSlotBoxIds {
    return [
      for (final powerup in _normalizedPowerupInventory)
        if (_isUnopenedMysteryBoxSlot(powerup)) powerup['id'] as String,
    ];
  }

  /// Total openable boxes (slot + queued overflow) — drives the "Open All"
  /// affordance, which only appears when there are at least two.
  int get _openableBoxCount => _openableSlotBoxIds.length + _queuedBoxCount;

  /// Trailing POWERUPS controls: "Open All" when ≥2 boxes are openable plus
  /// the queue chip.
  Widget? _powerupsHeaderTrailing() {
    final chip = _queuedBoxesChip();
    // §5.7b: OPEN ALL would open both demo boxes at once and skip beats 4-5
    // outright, and the multi-reel screen carries its own un-injected ad slots.
    final showOpenAll = !widget.demoMode && _openableBoxCount >= 2;
    if (chip == null && !showOpenAll) return null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showOpenAll) ...[
          _OpenAllButton(
            onTap: _isActing ? null : _openAllBoxes,
            loading: _actingPowerupId == _openAllActionId,
          ),
          if (chip != null) const SizedBox(width: 6),
        ],
        ?chip,
      ],
    );
  }

  /// Opens every openable box (slots + queued) in one action via the multi-reel
  /// screen. Feature-detects the batch endpoint and falls back to N single
  /// opens (queued omitted) on an older backend.
  Future<void> _openAllBoxes() async {
    if (_isActing) return;
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) return;
    final slotIds = _openableSlotBoxIds;
    final queued = _queuedBoxCount;
    final total = (slotIds.length + queued).clamp(0, 20);
    if (total < 1) return;

    _beginAction(_openAllActionId);
    try {
      await Navigator.of(context).push(
        PageRouteBuilder(
          opaque: false,
          pageBuilder: (_, _, _) => MultiCaseOpeningScreen(
            rarityByType: _serverRarityByType,
            dropOdds: _serverDropOdds,
            boxCount: total,
            includesQueued: queued > 0,
            onResults: (results) {
              for (final r in results) {
                final id = r['powerupId'] as String?;
                if (id != null) _optimisticallyApplyBoxOpen(id, r);
              }
            },
            openAll: () => _performOpenAll(token, slotIds),
            // Item 1 (batch 2026-08-10b) — one ad rerolls the whole bank.
            // Null (button hidden) unless the backend advertised
            // `boxRerollBatch`, a reroll ad unit exists, and we're not in the
            // demo. On Android there is no reroll ad unit, so this is always
            // null and the summary renders exactly as it does today.
            onRerollAll: _boxRerollBatchEnabled ? _rerollAllBoxPowerups : null,
          ),
          transitionsBuilder: (_, anim, _, child) =>
              FadeTransition(opacity: anim, child: child),
          transitionDuration: const Duration(milliseconds: 300),
        ),
      );
    } finally {
      _endAction();
      if (mounted) {
        unawaited(widget.onBoxOpened?.call());
      }
    }
  }

  /// Resolves the batch-open, feature-detecting the endpoint. On a 404 (or a
  /// non-JSON error body from an old backend) it falls back to N single opens
  /// for the known slot ids and omits queued boxes (which have no client ids).
  Future<List<Map<String, dynamic>>> _performOpenAll(
    String token,
    List<String> slotIds,
  ) async {
    try {
      final resp = await _api.openMysteryBoxBatch(
        identityToken: token,
        raceId: widget.raceId,
        powerupIds: slotIds,
        includeQueued: true,
        maxCount: 20,
      );
      return (resp['results'] as List?)?.cast<Map<String, dynamic>>() ??
          const [];
    } on ApiException catch (e) {
      if (e.statusCode == 404) return _fallbackSingleOpens(token, slotIds);
      rethrow;
    } on FormatException {
      // Old backend 404 with an empty/non-JSON body — treat as unavailable.
      return _fallbackSingleOpens(token, slotIds);
    }
  }

  /// Opens each slot box with a parallel single-open call and normalizes the
  /// results into the batch result shape (queued boxes are unreachable here).
  Future<List<Map<String, dynamic>>> _fallbackSingleOpens(
    String token,
    List<String> slotIds,
  ) async {
    final responses = await Future.wait([
      for (final id in slotIds)
        _api.openMysteryBox(
          identityToken: token,
          raceId: widget.raceId,
          powerupId: id,
        ),
    ]);
    final out = <Map<String, dynamic>>[];
    for (int i = 0; i < slotIds.length; i++) {
      final r = responses[i];
      final res = (r['result'] as Map<String, dynamic>?) ?? r;
      out.add({
        'powerupId': slotIds[i],
        'type': res['type'],
        'rarity': res['rarity'] ?? 'COMMON',
        'autoActivated': res['autoActivated'] == true,
        'queued': false,
      });
    }
    return out;
  }

  /// Item 11 — whether the backend is advertising the box-reroll feature.
  ///
  /// STRICTLY additive and read defensively: the flag only exists on a backend
  /// with `ADS_BOX_REROLL_ENABLED` on that also saw this client declare `ads`
  /// in `X-Client-Features`. Anything other than a literal `true` (absent,
  /// null, a string, an older backend, the demo service) hides the button.
  /// Demo mode never shows it regardless of what the payload says.
  bool get _boxRerollEnabled {
    if (widget.demoMode) return false;
    if (_powerupData?['boxReroll'] != true) return false;
    // No dedicated ad unit baked into this build => no button. Passing an
    // empty adUnitId to AdService would fall through to the EXTRA-SPIN unit
    // (see AdService._adUnitId), which is exactly the borrowing we removed.
    // An injected controller (widget tests) bypasses the define entirely.
    return widget.boxRerollAdController != null || AdService.boxRerollSupported;
  }

  /// Batch 2026-08-10b item 1 — whether the backend is advertising the BATCH
  /// box-reroll (REROLL ALL after OPEN ALL).
  ///
  /// A hand-copy of [_boxRerollEnabled], deliberately carrying BOTH of its
  /// guards: the demo-mode bail (OPEN ALL is separately suppressed in the demo
  /// today, but that suppression is not this getter's job to depend on) and
  /// the "no ad unit baked in => no button" tail. Anything other than a
  /// literal `true` — absent key, null, a string, an older backend, the demo
  /// service — hides the button and the Open All summary renders as today.
  bool get _boxRerollBatchEnabled {
    if (widget.demoMode) return false;
    if (_powerupData?['boxRerollBatch'] != true) return false;
    return widget.boxRerollAdController != null || AdService.boxRerollSupported;
  }

  /// Lazily-built rewarded-ad controller for the reroll. Its own AdMob unit
  /// and its own SSV customData prefix, so its grants can never be consumed by
  /// the daily-spinner extra spin (and vice versa).
  ExtraSpinAdController? _rerollAdCtrl;

  ExtraSpinAdController get _rerollAd => _rerollAdCtrl ??=
      widget.boxRerollAdController ??
      AdService(
        adUnitId: AdService.boxRerollAdUnitId,
        customDataPrefix: 'box_reroll',
      );

  static String _todayLocalDate() {
    final now = DateTime.now();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '${now.year}-$m-$d';
  }

  /// Shows the rewarded ad, then rerolls. Returns the new `{type, rarity}` or
  /// null when the user backed out / it failed (the reel then keeps its
  /// original result).
  Future<Map<String, dynamic>?> _rerollBoxPowerup(String powerupId) async {
    final token = widget.authService.authToken;
    final userId = _myUserId;
    if (token == null || token.isEmpty || userId.isEmpty) {
      return null;
    }

    final localDate = _todayLocalDate();
    try {
      if (!_rerollAd.isSupported) return null;
      if (!_rerollAd.isReady) {
        await _rerollAd.load(userId: userId, localDate: localDate);
      }
      if (!_rerollAd.isReady) {
        if (mounted) {
          showInfoToast(context, 'No ad available right now. Try again later.');
        }
        return null;
      }

      final earned = await _rerollAd.showAndAwaitReward();
      // Closed early: no grant was minted, so there is nothing to consume.
      if (!earned) return null;

      // Pass the SAME localDate the ad grant was minted with — never
      // recompute it inside the retry loop, which can span local midnight.
      final result = await _rerollWithRetry(token, powerupId, localDate);
      // Warm the next one up for a second box this session.
      unawaited(_rerollAd.load(userId: userId, localDate: localDate));
      // Item 4 (batch 2026-08-10b): do NOT refresh here. The case overlay is
      // non-opaque, so `_loadProgress` swapped the inventory row behind the
      // still-spinning reel to the NEW type and spoiled the reveal — exactly
      // the bug the original open path documents and avoids below. The
      // refresh already happens after the overlay closes, in
      // `_openMysteryBox`'s post-push block.
      return result;
    } on ApiException catch (e) {
      if (mounted) {
        showErrorToast(
          context,
          e.code == 'ALREADY_REROLLED'
              ? 'That box has already been rerolled.'
              : "Couldn't reroll that box.",
        );
      }
      return null;
    } catch (_) {
      if (mounted) showErrorToast(context, "Couldn't reroll that box.");
      return null;
    }
  }

  /// AdMob's server-side verification can land a few seconds after the ad
  /// closes on-device; until it does the backend answers 409 AD_NOT_VERIFIED.
  /// Same bounded retry the daily-spinner extra spin uses. If it never lands,
  /// the grant stays UNCONSUMED server-side — the next reroll attempt redeems
  /// it without a second ad.
  Future<Map<String, dynamic>> _rerollWithRetry(
    String token,
    String powerupId,
    String localDate,
  ) async {
    const maxAttempts = 5;
    for (var attempt = 0; ; attempt++) {
      try {
        return await _api.rerollPowerup(
          identityToken: token,
          raceId: widget.raceId,
          powerupId: powerupId,
          localDate: localDate,
        );
      } on ApiException catch (e) {
        final ssvLag =
            e.statusCode == 409 &&
            (e.code == 'AD_NOT_VERIFIED' ||
                e.message.toLowerCase().contains('not verified'));
        if (!ssvLag || attempt >= maxAttempts - 1) rethrow;
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
  }

  /// Batch 2026-08-10b item 1 — shows ONE rewarded ad, then rerolls every
  /// eligible box from the Open All batch together. Returns the new rows
  /// (keyed `powerupId`) or null when the user backed out / it failed, in
  /// which case the reel bank keeps its original results.
  Future<List<Map<String, dynamic>>?> _rerollAllBoxPowerups(
    List<String> powerupIds,
  ) async {
    final token = widget.authService.authToken;
    final userId = _myUserId;
    if (token == null || token.isEmpty || userId.isEmpty) return null;
    if (powerupIds.isEmpty) return null;

    final localDate = _todayLocalDate();
    try {
      if (!_rerollAd.isSupported) return null;
      if (!_rerollAd.isReady) {
        await _rerollAd.load(userId: userId, localDate: localDate);
      }
      if (!_rerollAd.isReady) {
        if (mounted) {
          showInfoToast(context, 'No ad available right now. Try again later.');
        }
        return null;
      }

      final earned = await _rerollAd.showAndAwaitReward();
      // Closed early: no grant was minted, so there is nothing to consume.
      if (!earned) return null;

      // Same localDate the grant was minted with, captured BEFORE the retry
      // loop — the loop can span local midnight.
      final response = await _rerollBatchWithRetry(
        token,
        powerupIds,
        localDate,
      );
      // Warm the next ad for a second Open All this session.
      unawaited(_rerollAd.load(userId: userId, localDate: localDate));
      // Item 4: NO _loadProgress() here — the reels are about to re-spin over
      // a non-opaque overlay. `_openAllBoxes`'s `finally` refreshes once the
      // overlay closes.
      final rows =
          (response['results'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .toList() ??
          const <Map<String, dynamic>>[];
      // A 200 carrying no rows at all shouldn't happen (every owned id comes
      // back, rerolled or skipped), but if it does the grant is already spent
      // server-side. Say so rather than re-spinning to identical results in
      // silence — and still return the (empty) list, so the button retires
      // instead of inviting a second wasted watch.
      if (rows.isEmpty && mounted) {
        showInfoToast(context, 'Nothing changed. Your rolls are unchanged.');
      }
      return rows;
    } on ApiException catch (e) {
      if (mounted) {
        final String message;
        if (e.code == 'NOTHING_TO_REROLL') {
          message = 'Nothing left to reroll.';
        } else if (e.statusCode == 404) {
          // Backend predates this batch. Feature detection should have hidden
          // the button; this is the belt-and-braces path.
          message = "Reroll isn't available right now.";
        } else if (e.statusCode == null &&
            e.message.toLowerCase().contains('timed out')) {
          // The batch may well have landed; `_openAllBoxes`'s finally will
          // reconcile the inventory once the overlay closes.
          message = 'Reroll may have completed. Check your boxes.';
        } else {
          message = "Couldn't reroll those boxes.";
        }
        showErrorToast(context, message);
      }
      return null;
    } on TimeoutException {
      if (mounted) {
        showErrorToast(context, 'Reroll may have completed. Check your boxes.');
      }
      return null;
    } catch (_) {
      if (mounted) showErrorToast(context, "Couldn't reroll those boxes.");
      return null;
    }
  }

  /// The batch twin of [_rerollWithRetry]: the same bounded 5×2s wait for
  /// AdMob's server-side verification to land, with the SAME localDate on every
  /// attempt.
  Future<Map<String, dynamic>> _rerollBatchWithRetry(
    String token,
    List<String> powerupIds,
    String localDate,
  ) async {
    const maxAttempts = 5;
    for (var attempt = 0; ; attempt++) {
      try {
        return await _api.rerollPowerupBatch(
          identityToken: token,
          raceId: widget.raceId,
          powerupIds: powerupIds,
          localDate: localDate,
        );
      } on ApiException catch (e) {
        final ssvLag =
            e.statusCode == 409 &&
            (e.code == 'AD_NOT_VERIFIED' ||
                e.message.toLowerCase().contains('not verified'));
        if (!ssvLag || attempt >= maxAttempts - 1) rethrow;
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
  }

  Future<void> _openMysteryBox(String boxId) async {
    if (_isActing) return;

    setState(() => _isActing = true);
    try {
      final token = widget.authService.authToken;
      if (token == null) {
        setState(() => _isActing = false);
        return;
      }

      await Navigator.of(context).push(
        PageRouteBuilder(
          opaque: false,
          pageBuilder: (_, _, _) => CaseOpeningScreen(
            // G8: the reel is a second full screen with two ad slots of its
            // own, which F5's fix does not reach.
            demoMode: widget.demoMode,
            // Additive, read defensively: absent on an older backend, in which
            // case the odds affordance hides and the reel keeps its bundled
            // rarity table (spec §5.3 / §6.3.B.8-10).
            dropOdds: _serverDropOdds,
            rarityByType: _serverRarityByType,
            openMysteryBox: () => _api.openMysteryBox(
              identityToken: token,
              raceId: widget.raceId,
              powerupId: boxId,
            ),
            // Item 11 — the rewarded-ad reroll. Null (button hidden) unless
            // the backend advertised the feature AND we're not in the demo.
            onReroll: _boxRerollEnabled ? _rerollBoxPowerup : null,
            onRevealed: (result) {
              // The overlay is non-opaque, so the inventory row stays visible
              // behind the reel. Mirror the server's state transition locally
              // only once the reel LANDS (spec §6): the box row becomes the
              // rolled HELD powerup (or empties if it auto-activated). Firing
              // this on the API response instead spoiled the result — and, for
              // an auto-activated Fanny Pack, deleted the row — behind the
              // still-spinning reel.
              _optimisticallyApplyBoxOpen(
                boxId,
                result['result'] as Map<String, dynamic>? ?? result,
              );
            },
          ),
          transitionsBuilder: (_, anim, _, child) =>
              FadeTransition(opacity: anim, child: child),
          transitionDuration: const Duration(milliseconds: 300),
        ),
      );

      if (!mounted) return;
      setState(() => _isActing = false);

      unawaited(widget.onBoxOpened?.call());
    } catch (e) {
      if (mounted) {
        setState(() => _isActing = false);
        showErrorToast(context, 'Failed to open mystery box');
      }
    }
  }

  /// Whether an active effect row on ME reads as a boost or a rival attack.
  /// Thin wrapper over the shared [effectIsBoost] helper so this screen and the
  /// races-tab badge cluster classify every effect identically. Deliberately
  /// does NOT consult the row's `onSelf` flag: the backend sets that to "this
  /// row targets the viewer" (true for rival attacks too), so classification is
  /// source-based only.
  bool _effectIsBoost(Map<String, dynamic> e) {
    return effectIsBoost(
      type: e['type'] is String ? e['type'] as String : null,
      sourceUserId: e['sourceUserId'] is String
          ? e['sourceUserId'] as String
          : null,
      myUserId: widget.authService.userId,
    );
  }

  Widget _buildActiveEffectsSection() {
    final rawEffects = _powerupData?['activeEffects'];
    final effects = rawEffects is List
        ? <Map<String, dynamic>>[
            for (final effect in rawEffects)
              if (effect is Map<String, dynamic> &&
                  (effect['onSelf'] == true ||
                      effect['targetUserId'] == widget.authService.userId))
                effect,
          ]
        : <Map<String, dynamic>>[];

    if (effects.isEmpty) {
      return const SizedBox.shrink();
    }

    final boosts = effects.where(_effectIsBoost).toList();
    final debuffs = effects.where((e) => !_effectIsBoost(e)).toList();
    final palette = AppColors.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(
            'ACTIVE EFFECTS',
            style: PixelText.title(size: 14, color: palette.textMid),
          ),
        ),
        if (boosts.isNotEmpty)
          _effectGroup(
            label: 'BOOSTS',
            icon: Icons.arrow_upward_rounded,
            tint: palette.feedBoost,
            effects: boosts,
            isBoost: true,
          ),
        if (boosts.isNotEmpty && debuffs.isNotEmpty) const SizedBox(height: 10),
        if (debuffs.isNotEmpty)
          _effectGroup(
            label: 'DEBUFFS',
            icon: Icons.arrow_downward_rounded,
            tint: palette.feedAttack,
            effects: debuffs,
            isBoost: false,
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Divider(
            color: palette.parchmentBorder.withValues(alpha: 0.5),
            height: 1,
          ),
        ),
      ],
    );
  }

  /// One polarity group of the active-effects block: a tinted header chip
  /// (BOOSTS ↑ green / DEBUFFS ↓ terracotta) over a matching tinted panel of
  /// effect rows, so helping-vs-hurting reads at a glance without parsing copy.
  Widget _effectGroup({
    required String label,
    required IconData icon,
    required Color tint,
    required List<Map<String, dynamic>> effects,
    required bool isBoost,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Icon(icon, size: 13, color: tint),
              ),
              const SizedBox(width: 6),
              Text(label, style: PixelText.title(size: 12, color: tint)),
              const SizedBox(width: 6),
              Text(
                '${effects.length}',
                style: PixelText.title(
                  size: 12,
                  color: tint.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  height: 1,
                  color: tint.withValues(alpha: 0.25),
                ),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: tint.withValues(alpha: 0.25)),
          ),
          child: Column(
            children: [
              for (var i = 0; i < effects.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: tint.withValues(alpha: 0.12),
                  ),
                _effectRow(effects[i], tint: tint, isBoost: isBoost),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// The live "Banked X/Y coins" subtitle for a viewer-owned Piggy Bank, or
  /// null to fall back to the static effect-rail copy.
  ///
  /// The backend attaches `piggyBank` (bankedCoins/coinCap/windowSteps) only to
  /// the owner's own PIGGY_BANK entry, and only when the snapshot will actually
  /// mint. An older backend omits it and a kill-switched snapshot never carries
  /// it, so this returns null unless `bankedCoins` is present and num-parseable
  /// (JSON numbers can arrive as `int` or `double`). `coinCap` is optional: a
  /// missing/unparseable cap degrades to "Banked X coins".
  String? _piggyBankSubtitle(Map<String, dynamic> e) {
    if (e['type'] != 'PIGGY_BANK') return null;
    final piggy = e['piggyBank'];
    if (piggy is! Map) return null;
    final banked = piggy['bankedCoins'];
    if (banked is! num) return null;
    final bankedCoins = banked.toInt();
    final cap = piggy['coinCap'];
    if (cap is num) {
      return 'Banked $bankedCoins/${cap.toInt()} coins';
    }
    return 'Banked $bankedCoins coins';
  }

  Widget _effectRow(
    Map<String, dynamic> e, {
    required Color tint,
    required bool isBoost,
  }) {
    final palette = AppColors.of(context);
    final type = e['type'] as String?;
    final name = type == null ? 'Unknown' : PowerupCopy.nameFor(type);
    // Shipped chain: short description, else the FULL description, else
    // empty. 11 of 26 types have no short copy and rely on the
    // description here — omitting the line would blank their subtitle.
    // A viewer-owned Piggy Bank swaps in a live "banked so far" counter when
    // the backend attaches the optional `piggyBank` snapshot. Absent/malformed
    // (an older backend, or a kill-switched snapshot) falls through to the
    // static copy unchanged — the field and every subfield are read defensively
    // and parsed num-safely, since JSON numbers aren't guaranteed to be `int`.
    final desc =
        _piggyBankSubtitle(e) ?? PowerupCopy.effectRailSubtitleFor(type);
    // A debuff leads with who did it — the attacker matters more than the
    // mechanic, and leading keeps the name safe from end-ellipsis.
    final attacker = isBoost
        ? null
        : _displayNameForUser(e['sourceUserId'] as String?);
    final subtitle = attacker == null
        ? desc
        : (desc.isEmpty ? 'from @$attacker' : 'from @$attacker · $desc');
    final expiresAtValue = e['expiresAt'];
    final expiresAtStr = expiresAtValue is String ? expiresAtValue : null;

    String timeLabel;
    if (expiresAtStr != null) {
      final expiresAt = DateTime.tryParse(expiresAtStr);
      if (expiresAt == null) {
        timeLabel = 'Until used';
      } else {
        final remaining = expiresAt.difference(_countdownNow);
        if (remaining.isNegative) {
          timeLabel = 'Expiring...';
        } else if (remaining.inHours > 0) {
          timeLabel = '${remaining.inHours}h ${remaining.inMinutes % 60}m';
        } else if (remaining.inMinutes > 0) {
          timeLabel = '${remaining.inMinutes}m ${remaining.inSeconds % 60}s';
        } else {
          timeLabel = '${remaining.inSeconds}s';
        }
      }
    } else {
      timeLabel = 'Until used';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: PowerupIcon(type: type ?? '', size: 22, spinning: true),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: PixelText.title(size: 13, color: palette.textDark),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: PixelText.body(size: 11, color: palette.textMid),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isBoost ? palette.woodDark : palette.error,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              timeLabel,
              style: PixelText.title(size: 11, color: palette.textLight),
            ),
          ),
        ],
      ),
    );
  }

  /// "N queued" mystery-box chip for the POWERUPS section header. Null when
  /// nothing is queued so the header renders without a trailing widget.
  Widget? _queuedBoxesChip() {
    if (_queuedBoxCount <= 0) return null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.of(context).parchment.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 18, height: 20, child: SpinningCrate(size: 16)),
          const SizedBox(width: 4),
          Text(
            '$_queuedBoxCount queued',
            style: PixelText.body(
              size: 11,
              color: AppColors.of(context).coinDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInventoryContent() {
    final inventory = _normalizedPowerupInventory;
    final slotCount = _readInt(_powerupData?['powerupSlots'], fallback: 3);

    return Column(
      key: widget.tutorialPowerupsKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(slotCount, (i) {
            final isExtraSlot = i >= 3;
            if (i < inventory.length) {
              final pw = inventory[i];
              final status = pw['status'] as String? ?? 'HELD';
              final isMysteryBox = status == 'MYSTERY_BOX';

              // The gate is consulted BEFORE either branch acts. It stays null
              // in the real app, so this is a no-op outside the demo.
              bool allowed() => widget.demoTapGate?.call(pw) ?? true;

              if (isMysteryBox) {
                final boxId = _isUnopenedMysteryBoxSlot(pw)
                    ? pw['id'] as String
                    : null;
                return ItemSlot(
                  state: ItemSlotState.mysteryBox,
                  isExtraSlot: isExtraSlot,
                  onTap: _isActing || boxId == null
                      ? null
                      : () {
                          if (!allowed()) return;
                          _openMysteryBox(boxId);
                        },
                );
              }

              final rawType = pw['type'];
              final rawRarity = pw['rarity'];
              return ItemSlot(
                state: ItemSlotState.held,
                powerupType: rawType is String ? rawType : '',
                rarity: rawRarity is String ? rawRarity : null,
                isExtraSlot: isExtraSlot,
                onTap: _isActing || rawType is! String || rawType.trim().isEmpty
                    ? null
                    : () {
                        if (!allowed()) return;
                        _showPowerupActions(pw);
                      },
              );
            } else {
              return ItemSlot(
                state: ItemSlotState.empty,
                isExtraSlot: isExtraSlot,
              );
            }
          }),
        ),
        ..._buildGlobalPowerupStash(),
      ],
    );
  }

  /// Renders a "use from your stash" affordance for each coin-purchased powerup
  /// the user owns globally (e.g. Imposter). Tapping redeems one into the race
  /// and runs the normal use/target flow. Hidden entirely if the stash is empty
  /// (which is also the case on an older backend without the inventory endpoint).
  List<Widget> _buildGlobalPowerupStash() {
    final entries =
        _globalPowerupInventory.entries
            // Retired types remain readable in history but never expose a dead
            // USE action if an old backend still returns inventory residue.
            .where((e) => e.value > 0 && !_hiddenPowerupTypes.contains(e.key))
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key));
    if (entries.isEmpty) return const [];

    return [
      const SizedBox(height: 12),
      Text(
        'YOUR STASH',
        style: PixelText.title(size: 13, color: AppColors.of(context).textMid),
      ),
      const SizedBox(height: 6),
      for (final e in entries)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              SizedBox(width: 24, child: PowerupIcon(type: e.key, size: 22)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${PowerupCopy.nameFor(e.key)} x${e.value}',
                  style: PixelText.body(
                    size: 14,
                    color: AppColors.of(context).textDark,
                  ),
                ),
              ),
              PillButton(
                key: Key('stash-use-${e.key}'),
                label: 'USE',
                variant: PillButtonVariant.secondary,
                fontSize: 11,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                // Item 12: only the row actually redeeming spins.
                loading: _actingPowerupId == 'stash:${e.key}',
                // Confirm first — a stash item cost coins, so it never gets
                // spent on a single tap the way a free box drop does.
                onPressed: _isActing
                    ? null
                    : () => _showStashPowerupActions(e.key, e.value),
              ),
            ],
          ),
        ),
    ];
  }

  String _relativeTime(String? isoTimestamp) {
    if (isoTimestamp == null) return '';
    final dt = DateTime.tryParse(isoTimestamp);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${(diff.inDays / 7).floor()}w';
  }

  /// Whether to show the Share action: any ACCEPTED participant can share a
  /// race that's still open (PENDING/ACTIVE). Completed/cancelled races aren't
  /// shareable — there's nothing to join.
  bool _canShareRace() {
    // §5.6: the demo never mints a share link for a race that doesn't exist.
    if (widget.demoMode) return false;
    final race = _race;
    if (race == null) return false;
    final status = race['status'] as String?;
    return race['myStatus'] == 'ACCEPTED' &&
        status != 'COMPLETED' &&
        status != 'CANCELLED';
  }

  /// Mints (or reuses) the race's share link via the backend and opens the
  /// native share sheet so the user can send it over iMessage/etc. The link
  /// opens the app straight into this race if installed, or a landing page +
  /// store otherwise.
  Future<void> _shareRace() async {
    if (_sharingRace) return;
    final identityToken = widget.authService.authToken;
    if (identityToken == null || identityToken.isEmpty) return;

    setState(() => _sharingRace = true);
    try {
      final result = await _api.createRaceShareLink(
        identityToken: identityToken,
        raceId: widget.raceId,
      );
      final url = result['url'] as String?;
      if (url == null || url.isEmpty) {
        throw const ApiException('Could not create a share link.');
      }
      if (!mounted) return;
      final raceName = raceDisplayName(
        _race?['seedKind'] as String?,
        _race?['name'] as String? ?? 'a race',
      );
      // Taunt with my live step count in this race when available — a
      // personal challenge opens better than a generic invite.
      // `myTotalSteps` is served top-level because my own row may be off-page;
      // the array scan stays as the fallback for a backend that omits it, and
      // a null on both paths keeps the existing generic copy.
      final participants =
          (_race?['participants'] as List?)?.cast<Map<String, dynamic>>() ??
          const [];
      final mySteps =
          _summaryMyTotalSteps ??
          participants
              .where((p) => (p['userId'] as String?) == _myUserId)
              .map((p) => (p['totalSteps'] as num?)?.toInt() ?? 0)
              .fold<int>(0, (a, b) => a > b ? a : b);
      final text = mySteps > 0
          ? 'I\'ve logged ${_formatSteps(mySteps)} steps in "$raceName" on '
                'Bara. Think you can catch me? $url'
          : 'Race me in "$raceName" on Bara. Bet you can\'t keep up! $url';
      await shareText(
        _shareButtonKey.currentContext ?? context,
        text,
        subject: 'Race me on Bara',
      );
      unawaited(
        _activationAnalytics.record(
          'race_share_completed',
          context: {'race_id': widget.raceId},
        ),
      );
    } on ApiException catch (e) {
      if (mounted) showErrorToast(context, e.message);
    } catch (e) {
      if (mounted) showErrorToast(context, 'Could not share: $e');
    } finally {
      if (mounted) setState(() => _sharingRace = false);
    }
  }

  /// Whether to show the per-race notification mute toggle. It silences both
  /// placement and chat pushes, which only fire for live races you're running
  /// in, so the control is only shown for an ACTIVE race the user has accepted.
  bool _canMutePlacementAlerts() {
    // §5.6: the mute toggle is a write against a race that doesn't exist.
    if (widget.demoMode) return false;
    final race = _race;
    if (race == null) return false;
    // Tournament matchups own their lifecycle in the bracket UI. Keep every
    // secondary control out of this header, including a relocated mute toggle.
    if (race['tournamentId'] != null) return false;
    // A spectator gets no pushes for this race, and the toggle is a write.
    if (_isSpectator) return false;
    return race['myStatus'] == 'ACCEPTED' && race['status'] == 'ACTIVE';
  }

  /// The backend stamps the one allowed destructive transition. This strict
  /// gate is intentionally more conservative than deriving eligibility from
  /// local state: an old/mid-rollout backend omitting `leaveAction` cannot be
  /// prompted into a mutation it does not yet honour.
  String? get _stampedLeaveAction {
    if (widget.demoMode || _isSpectator) return null;
    final race = _race;
    if (race == null || race['tournamentId'] != null) return null;
    if (race['myStatus'] != 'ACCEPTED' || race['isCreator'] == true) {
      return null;
    }
    // The membership re-check is only meaningful against a FULL roster. On a
    // paged payload the viewer's own row is routinely off-page, and re-scanning
    // would silently withhold the leave/forfeit control from a real
    // participant; `myStatus == 'ACCEPTED'` (checked just above, from the
    // backend's own lookup) already establishes membership there.
    if (!_serverHonouredParticipantsPaging) {
      final participants = race['participants'];
      if (participants is! List ||
          !participants.whereType<Map>().any((p) => p['userId'] == _myUserId)) {
        return null;
      }
    }
    final action = race['leaveAction'];
    if (action == 'LEAVE' && race['status'] == 'PENDING') return action;
    if (action == 'FORFEIT' && race['status'] == 'ACTIVE') return action;
    return null;
  }

  bool _canShowCreatorOptions() {
    final race = _race;
    if (widget.demoMode || _isSpectator || race == null) return false;
    return race['tournamentId'] == null &&
        race['isCreator'] == true &&
        (race['status'] == 'PENDING' || race['status'] == 'ACTIVE');
  }

  bool _hasRaceOptions() =>
      _canMutePlacementAlerts() ||
      _canShowCreatorOptions() ||
      _stampedLeaveAction != null;

  /// Flips the per-race notification mute, covering BOTH placement-change and
  /// chat pushes. Optimistic: update the icon immediately, persist both backend
  /// flags together, and revert on failure.
  Future<void> _togglePlacementMute() async {
    if (_togglingPlacementMute) return;
    final identityToken = widget.authService.authToken;
    if (identityToken == null || identityToken.isEmpty) return;

    final next = !_placementMuted;
    setState(() {
      _placementMuted = next;
      _togglingPlacementMute = true;
    });
    // Keep the chat service's local mute state in sync without a second
    // round-trip (the API call below is the source of truth).
    _chat?.setMutedFromServer(next);
    try {
      await Future.wait([
        _api.setRacePlacementMute(
          identityToken: identityToken,
          raceId: widget.raceId,
          muted: next,
        ),
        _api.setRaceChatMute(
          identityToken: identityToken,
          raceId: widget.raceId,
          muted: next,
        ),
      ]);
      if (mounted) {
        showInfoToast(
          context,
          next
              ? 'Muted notifications for this race'
              : 'Notifications on for this race',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _placementMuted = !next); // revert
        _chat?.setMutedFromServer(!next);
        showErrorToast(context, 'Couldn’t update notifications: $e');
      }
    } finally {
      if (mounted) setState(() => _togglingPlacementMute = false);
    }
  }

  void _showRaceOptionsSheet() {
    final status = _race?['status'] as String? ?? '';
    final canMute = _canMutePlacementAlerts();
    final canManage = _canShowCreatorOptions();
    final leaveAction = _stampedLeaveAction;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.of(context).parchment,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'RACE OPTIONS',
              style: PixelText.title(
                size: 18,
                color: AppColors.of(context).textDark,
              ),
            ),
            const SizedBox(height: 16),
            if (canMute) ...[
              PillButton(
                label: _placementMuted
                    ? 'NOTIFICATIONS ON'
                    : 'NOTIFICATIONS OFF',
                variant: PillButtonVariant.secondary,
                fontSize: 13,
                fullWidth: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                onPressed: _togglingPlacementMute
                    ? null
                    : () {
                        Navigator.of(context).pop();
                        _togglePlacementMute();
                      },
              ),
              const SizedBox(height: 10),
            ],
            if (canManage) ...[
              PillButton(
                label: status == 'PENDING' ? 'INVITE FRIENDS' : 'INVITE MORE',
                variant: PillButtonVariant.secondary,
                fontSize: 13,
                fullWidth: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                onPressed: _isActing
                    ? null
                    : () {
                        Navigator.of(context).pop();
                        _inviteMore();
                      },
              ),
              const SizedBox(height: 10),
            ],
            if (canManage && status == 'PENDING') ...[
              PillButton(
                label: 'EDIT SETTINGS',
                variant: PillButtonVariant.secondary,
                fontSize: 13,
                fullWidth: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                onPressed: _isActing
                    ? null
                    : () {
                        Navigator.of(context).pop();
                        _editRaceSettings();
                      },
              ),
            ],
            if (canManage || leaveAction != null) const SizedBox(height: 10),
            if (leaveAction != null)
              PillButton(
                label: leaveAction == 'LEAVE' ? 'LEAVE RACE' : 'FORFEIT RACE',
                variant: PillButtonVariant.accent,
                fontSize: 13,
                fullWidth: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                onPressed: _isActing
                    ? null
                    : () {
                        Navigator.of(context).pop();
                        _confirmStampedLeave(leaveAction);
                      },
              ),
            if (canManage)
              PillButton(
                label: 'CANCEL RACE',
                variant: PillButtonVariant.accent,
                fontSize: 13,
                fullWidth: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                onPressed: _isActing
                    ? null
                    : () {
                        Navigator.of(context).pop();
                        _showCancelConfirmation();
                      },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmStampedLeave(String action) async {
    final isForfeit = action == 'FORFEIT';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        child: TrailSign(
          width: 330,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isForfeit ? 'FORFEIT THE RACE?' : 'LEAVE THE RACE?',
                style: PixelText.title(
                  size: 18,
                  color: AppColors.of(context).textDark,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              Text(
                isForfeit
                    ? _stampedForfeitConsequence()
                    : 'Your place will be removed and this race’s projected prize pot will update.',
                style: PixelText.body(
                  size: 14,
                  color: AppColors.of(context).textMid,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              PillButton(
                label: isForfeit ? 'KEEP RACING' : 'STAY IN RACE',
                variant: PillButtonVariant.secondary,
                fullWidth: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                onPressed: () => Navigator.of(dialogContext).pop(false),
              ),
              const SizedBox(height: 10),
              PillButton(
                label: isForfeit ? 'FORFEIT RACE' : 'LEAVE RACE',
                variant: PillButtonVariant.accent,
                fullWidth: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                onPressed: () => Navigator.of(dialogContext).pop(true),
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true || !mounted || _isActing) return;
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) return;
    setState(() => _isActing = true);
    try {
      await _api.leaveRace(identityToken: token, raceId: widget.raceId);
      await _refreshWallet();
      if (!mounted) return;
      if (!isForfeit) {
        Navigator.of(context).pop(true);
        return;
      }
      await _loadDetails();
      await _loadProgress();
    } on ApiException catch (e) {
      if (mounted) showErrorToast(context, e.message);
    } catch (_) {
      if (mounted) {
        showErrorToast(context, 'Couldn’t update this race. Try again.');
      }
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  String _stampedForfeitConsequence() {
    final progress = _progressState.data ?? _progress;
    final participants = progress?['participants'];
    var mySteps = 0;
    if (participants is List) {
      for (final participant in participants.whereType<Map>()) {
        if (participant['userId'] == _myUserId) {
          final rawSteps = participant['totalSteps'];
          mySteps = rawSteps is num ? rawSteps.toInt() : 0;
          break;
        }
      }
    }
    if (_prizePool?.funded == true) {
      return mySteps > 0
          ? 'Your score freezes now and you cannot receive a payout. Because you have walked steps, your funded spot stays in the final prize pool and it is redistributed among eligible finishers.'
          : 'Your score freezes now and you cannot receive a payout. Because you have not walked any steps, your funded amount is removed from the projected prize pool.';
    }
    return 'Your score freezes now. You will not be eligible for a payout, and the final prize pot is recalculated under the race rules.';
  }

  bool get _canPostMessage {
    final race = _race;
    if (race == null) return false;
    // Spectator-ness is derived from the participants list, not from a backend
    // field (spec §5), so a differently-versioned backend can never hand a
    // bracket spectator a composer whose posts the server would 403.
    if (_isSpectator) return false;
    return race['myStatus'] == 'ACCEPTED' &&
        race['status'] != 'COMPLETED' &&
        race['status'] != 'CANCELLED';
  }

  Future<void> _sendMessage() async {
    final chat = _chat;
    if (chat == null) return;
    final text = _messageInput.text.trim();
    if (text.isEmpty || _sendingMessage) return;
    setState(() => _sendingMessage = true);
    _messageInput.clear();
    await chat.send(text);
    if (mounted) setState(() => _sendingMessage = false);
  }

  Future<void> _confirmDeleteMessage(String messageId) async {
    final chat = _chat;
    if (chat == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete message?'),
        actions: [
          ModalActionButton(
            onPressed: () => Navigator.pop(ctx, false),
            label: 'Cancel',
            variant: ModalActionVariant.secondary,
          ),
          ModalActionButton(
            onPressed: () => Navigator.pop(ctx, true),
            label: 'Delete',
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await chat.deleteMessage(messageId);
    }
  }

  Map<String, String> _participantNames() {
    final participants =
        (_progress?['participants'] as List?)?.cast<Map<String, dynamic>>() ??
        [];
    final actorNames = <String, String>{};
    for (final p in participants) {
      final uid = p['userId'] as String? ?? '';
      final name = p['displayName'] as String? ?? '???';
      if (uid.isNotEmpty) actorNames[uid] = name;
    }
    return actorNames;
  }

  /// Two-tab bounded panel replacing the old merged activity section.
  Widget _buildActivityTabsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: ArcadeTabSelector(
            labels: const ['ACTIVITY', 'CHAT'],
            activeIndex: _activityTabIndex,
            onChanged: _onTabChanged,
            unread: [false, _chatHasUnread],
          ),
        ),
        const SizedBox(height: 10),
        _sectionCard(
          padding: const EdgeInsets.all(10),
          child: SizedBox(
            height: 400,
            child: _activityTabIndex == 0
                ? _buildActivityTab()
                : _buildChatTab(),
          ),
        ),
      ],
    );
  }

  /// Preview mode's stand-in for the two tabs whose endpoints still 403 a
  /// non-participant. Nothing is fetched behind it.
  Widget _buildPreviewLockedTab(Key key, String line) {
    final colors = AppColors.of(context);
    return Center(
      key: key,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: 30,
              color: colors.textMid.withValues(alpha: 0.55),
            ),
            const SizedBox(height: 10),
            Text(
              line,
              textAlign: TextAlign.center,
              style: PixelText.body(
                size: 15,
                color: colors.textMid.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'JOIN TO SEE THIS',
              textAlign: TextAlign.center,
              style: PixelText.title(
                size: 12,
                color: colors.textMid.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityTab() {
    if (_isPreviewViewer) {
      return _buildPreviewLockedTab(
        const Key('race-preview-locked-activity'),
        'The race feed opens up once you’re in.',
      );
    }
    final feed = _feed;
    final actorNames = _participantNames();
    final events = feed?.events ?? const <RaceFeedEvent>[];
    final isLoading = feed?.isLoading ?? false;
    final hasError = feed != null && feed.lastError != null && events.isEmpty;

    if (feed == null || (events.isEmpty && isLoading)) {
      return const LoadingSkeleton(
        child: Column(
          children: [
            SkeletonLine(width: double.infinity, height: 14),
            SizedBox(height: 8),
            SkeletonLine(width: 220, height: 14),
          ],
        ),
      );
    }
    if (hasError) {
      return LoadErrorPanel(
        title: 'Couldn’t load activity',
        message: 'Check your connection and try again.',
        onRetry: _streams?.refreshNow ?? feed.loadInitial,
      );
    }
    if (events.isEmpty) {
      return _buildTabEmptyState('No activity yet. Race is young!');
    }
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        for (final e in events) _buildActivityItem(e, actorNames),
        if (feed.hasMore)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: TextButton(
                onPressed: isLoading ? null : feed.loadMore,
                child: Text(
                  isLoading ? 'Loading…' : 'Load older',
                  style: PixelText.body(
                    size: 13,
                    color: AppColors.of(context).accent,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildActivityItem(RaceFeedEvent e, Map<String, String> actorNames) {
    final actorId = e.actorUserId ?? '';
    return FeedBubble(
      eventType: e.eventType,
      powerupType: e.powerupType,
      description: e.description,
      actorName: actorNames[actorId] ?? '???',
      relativeTime: _relativeTime(e.createdAt.toUtc().toIso8601String()),
      actorIsUser: actorId == _myUserId,
    );
  }

  Widget _buildChatTab() {
    if (_isPreviewViewer) {
      return _buildPreviewLockedTab(
        const Key('race-preview-locked-chat'),
        'Race chat is for the runners in it.',
      );
    }
    final chat = _chat;
    final messages = chat?.messages ?? const <RaceChatMessage>[];
    final isLoading = chat?.isLoading ?? false;
    final hasError = chat != null && chat.lastError != null && messages.isEmpty;

    Widget body;
    if (chat == null || (messages.isEmpty && isLoading)) {
      body = const LoadingSkeleton(
        child: Column(
          children: [
            SkeletonLine(width: double.infinity, height: 14),
            SizedBox(height: 8),
            SkeletonLine(width: 220, height: 14),
          ],
        ),
      );
    } else if (hasError) {
      body = LoadErrorPanel(
        title: 'Couldn’t load chat',
        message: 'Check your connection and try again.',
        onRetry: () => _streams?.openChat(muted: _race?['myChatMuted'] == true),
      );
    } else if (messages.isEmpty) {
      body = _buildTabEmptyState('No messages yet. Say hi!');
    } else {
      body = ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        // B7 — dragging the message list dismisses the keyboard (scoped to the
        // chat tab; no global unfocus wrapper).
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        // IM-style: newest at the bottom, anchored there; scroll up for older.
        // messages are newest-first, so reverse lays child 0 (newest) at the
        // bottom and the "Load older" control ends up at the top.
        reverse: true,
        children: [
          for (final m in messages) _buildChatItem(m),
          if (chat.hasMore)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: TextButton(
                  onPressed: isLoading ? null : chat.loadMore,
                  child: Text(
                    isLoading ? 'Loading…' : 'Load older',
                    style: PixelText.body(
                      size: 13,
                      color: AppColors.of(context).accent,
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: body),
        _buildMessageComposer(),
      ],
    );
  }

  Widget _buildChatItem(RaceChatMessage m) {
    final mine = m.senderId == null
        ? (m.pending || m.failed)
        : m.senderId == _myUserId;
    return _ChatBubble(
      message: m,
      isMine: mine,
      onLongPress: mine && !m.pending && !m.failed
          ? () => _confirmDeleteMessage(m.id)
          : null,
    );
  }

  Widget _buildTabEmptyState(String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: PixelText.body(
            size: 16,
            color: AppColors.of(context).textMid.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageComposer() {
    final race = _race;
    if (race == null) return const SizedBox.shrink();
    if (!_canPostMessage) {
      final status = race['status'] as String? ?? '';
      final myStatus = race['myStatus'] as String? ?? '';
      final reason = _isSpectator
          ? "You're spectating. Chat is read-only."
          : status == 'COMPLETED'
          ? 'This race is finished. Chat is read-only.'
          : status == 'CANCELLED'
          ? 'This race was cancelled. Chat is read-only.'
          : myStatus == 'INVITED'
          ? 'Accept the invite to post in chat.'
          : 'You can\'t post in this chat.';
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        color: AppColors.of(context).parchmentDark.withValues(alpha: 0.3),
        child: Text(
          reason,
          style: PixelText.body(size: 14, color: AppColors.of(context).textMid),
          textAlign: TextAlign.center,
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: AppColors.of(context).parchmentLight,
        border: Border(
          top: BorderSide(
            color: AppColors.of(context).textMid.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _messageInput,
              focusNode: _messageFocus,
              minLines: 1,
              maxLines: 4,
              maxLength: 500,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
              // B7 — tapping outside the field dismisses the keyboard. The send
              // button is a separate tap target, so it still fires. Scoped to
              // the composer; no global unfocus wrapper on the screen.
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              decoration: InputDecoration(
                hintText: 'Message…',
                hintStyle: PixelText.body(
                  size: 16,
                  color: AppColors.of(context).textMid,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                counterText: '',
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            icon: _sendingMessage
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send),
            color: AppColors.of(context).accent,
            onPressed: _sendingMessage ? null : _sendMessage,
          ),
        ],
      ),
    );
  }

  Widget _buildCompletedContent() {
    if (_progressState.shouldShowInitialLoading) {
      return Column(
        children: [
          _buildRaceHero(runners: const [], chips: const []),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: KeyedSubtree(
              key: Key('race-detail-completed-progress-skeleton'),
              child: _RaceProgressSkeleton(),
            ),
          ),
        ],
      );
    }
    if (_progressState.isError && !_progressState.hasData) {
      return Column(
        children: [
          _buildRaceHero(runners: const [], chips: const []),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: KeyedSubtree(
              key: const Key('race-detail-completed-progress-error'),
              child: LoadErrorPanel(
                title: 'Couldn’t load final standings',
                message: 'Check your connection and try again.',
                onRetry: _loadProgress,
              ),
            ),
          ),
        ],
      );
    }
    final winner = _race!['winner'] as Map<String, dynamic>?;
    // TR-402/404: team races record winnerTeam (winnerUserId stays null), and
    // a completed team race with no winnerTeam is a TIE — never the plain
    // individual "No winner" state.
    final isTeamRace = TeamRace.isTeamRace(_race!);
    final winnerTeam = TeamRace.winnerTeam(_race!);
    final participants = orderRaceParticipantsForDisplay(
      ((_progressState.data ?? _progress)?['participants'] as List?)
              ?.cast<Map<String, dynamic>>() ??
          // Only fall back to the details array when it's known-full — once
          // paging is honoured that array can be a single page, and a failed
          // progress load must not render a truncated "final standings"
          // board as if it were authoritative.
          (_serverHonouredParticipantsPaging
              ? null
              : (_race!['participants'] as List?)
                    ?.cast<Map<String, dynamic>>()) ??
          [],
    );
    final completedLeaderSteps = _leaderSteps(participants);
    final winnerId = winner?['id'] as String?;
    final winnerEntry = participants.firstWhere(
      (p) => (p['userId'] as String?) == winnerId,
      orElse: () => const <String, dynamic>{},
    );
    final winnerAccessories =
        (winnerEntry['accessories'] as List?)?.cast<Map<String, dynamic>>() ??
        const <Map<String, dynamic>>[];
    final winnerAnimal = animalFromJson(winnerEntry['animal']);

    // Item 4 — the solo podium. Null whenever a podium can't be drawn (team
    // race, or fewer than two finishers), in which case the original winner
    // card renders untouched. Payout amounts come from the race's own tiers,
    // so an unfunded race simply shows no coin lines.
    final podiumFinishers =
        (!isTeamRace &&
            RacePodium.canRender(RacePodium.occupantCount(participants)))
        ? RacePodium.finishersFromParticipants(
            participants,
            payoutTiers: parsePayoutTiers(_race),
            viewerUserId: _myUserId,
          )
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The finished race on the race-day course, final positions held.
        _buildRaceHero(
          chips: [
            _heroChip(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.emoji_events_rounded,
                    size: 16,
                    color: AppColors.of(context).pillGold,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'RACE COMPLETE',
                    style: PixelText.title(size: 13, color: Colors.white),
                  ),
                ],
              ),
            ),
            // A finished funded race still shows what the pool paid out.
            if (_prizePool != null &&
                (_prizePool!.funded || _prizePool!.coins > 0)) ...[
              const Spacer(),
              _prizeChip(),
            ],
          ],
          runners: [
            for (final p in participants)
              GoalTrackRunner(
                name: p['displayName'] as String? ?? '???',
                progress: _leaderRelativeProgress(
                  p['totalSteps'],
                  completedLeaderSteps,
                ),
                isUser: (p['userId'] as String?) == _myUserId,
                profilePhotoUrl: p['profilePhotoUrl'] as String?,
                accessories:
                    (p['accessories'] as List?)?.cast<Map<String, dynamic>>() ??
                    const [],
                animal: animalFromJson(p['animal']),
              ),
          ],
        ),
        const SizedBox(height: 16),

        // WINNER — celebratory podium card.
        StaggerIn(
          index: 0,
          child: Column(
            children: [
              _checkerSectionHeader(
                isTeamRace
                    ? 'WINNING TEAM'
                    : (podiumFinishers != null ? 'PODIUM' : 'WINNER'),
              ),
              _sectionCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    if (isTeamRace)
                      _buildTeamWinnerBoard(winnerTeam, participants)
                    // Item 4: solo races end on a podium. Team races keep the
                    // winning-team board; a race with a single finisher keeps
                    // the old winner card (one plinth reads as broken).
                    else if (podiumFinishers != null)
                      RacePodium(
                        finishers: podiumFinishers,
                        // The results popup fires the shared confetti at
                        // screen level; here the podium owns it.
                        showConfetti: !widget.demoMode,
                      )
                    else if (winner != null) ...[
                      RacerAvatar(
                        rank: 1,
                        accessories: winnerAccessories,
                        size: 64,
                        animal: winnerAnimal,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        winner['displayName'] is String
                            ? atName(winner['displayName'] as String)
                            : 'Unknown',
                        style: PixelText.title(
                          size: 22,
                          color: AppColors.of(context).textDark,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      const PlacementPill(placement: 1),
                    ] else
                      Text(
                        'No winner',
                        style: PixelText.title(
                          size: 18,
                          color: AppColors.of(context).textMid,
                        ),
                        textAlign: TextAlign.center,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // FINAL STANDINGS
        StaggerIn(
          key: _standingsVisibilityKey,
          index: 1,
          child: Column(
            children: [
              _checkerSectionHeader('FINAL STANDINGS'),
              _sectionCard(
                padding: const EdgeInsets.all(8),
                child: isTeamRace
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: _buildTeamGroupedRows(participants),
                      )
                    : _standingsList(
                        participants,
                        hasMore: _participantsHasMore,
                        isLoadingMore: _participantsLoadingMore,
                      ),
              ),
            ],
          ),
        ),
        SizedBox(height: 18),

        // ACTIVITY / CHAT — still viewable after the race ends. The composer
        // auto-disables (read-only) via _canPostMessage.
        StaggerIn(index: 2, child: _buildActivityTabsSection()),
        SizedBox(height: 24),
      ],
    );
  }

  Widget _buildCancelledContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: 64),
        Icon(
          Icons.cancel_outlined,
          size: 48,
          color: AppColors.of(context).textLight.withValues(alpha: 0.75),
        ),
        SizedBox(height: 12),
        Text(
          'This race was cancelled',
          style: PixelText.title(
            size: 18,
            color: AppColors.of(context).textLight,
          ).copyWith(shadows: _headerTextShadows),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: 24),
      ],
    );
  }

  // -- Even-split payout summary (batch 2026-07-27, item 9) -----------------
  //
  // Seeded daily/weekly challenges are TOP_HALF, so a 300-runner field pays 150
  // identical places. The podium row ("1ST / 2ND / 3RD / +147 MORE") answered
  // none of the questions a runner in 62nd actually has, and 150 rows in a card
  // is unreadable. This block answers them in four lines and keeps the full
  // list one tap away.
  //
  // EVERY figure is read off `payoutTiers` — the server owns the payout math.

  /// True when every paid place wins the same amount, i.e. the pool is split
  /// evenly (TOP_HALF, ALL_BUT_LAST). A single-tier race (winner takes all) is
  /// deliberately excluded: "the top 1 split it evenly" is nonsense, and the
  /// existing podium row already says it better.
  bool _isEvenSplitPayout(List<PayoutTier> tiers) =>
      tiers.length >= 2 && tiers.every((t) => t.amount == tiers.first.amount);

  /// The preset in plain words. Falls back to a preset-agnostic sentence so an
  /// unknown/absent `payoutPreset` (a newer backend, a frozen client) still
  /// reads correctly rather than rendering a blank headline.
  String _evenSplitHeadline(int paidPlaces) {
    switch (_race?['payoutPreset']) {
      case 'TOP_HALF':
        return 'Top half splits the pool evenly';
      case 'ALL_BUT_LAST':
        return 'Everyone but last splits the pool evenly';
      default:
        return 'The top $paidPlaces split the pool evenly';
    }
  }

  // -- Top-heavy (graded-curve) payout summary ------------------------------
  //
  // A seeded challenge stamped `payoutCurve: "GEOMETRIC"` still serves a graded
  // preset, but its tiers DECAY instead of being identical: 1st takes ~30% of
  // the pool. The even-split card would be a lie, and the podium row buries the
  // one fact that changed — winning is now worth chasing.
  //
  // `payoutCurve` is deliberately NOT serialized to clients, so the tier
  // amounts are the only signal. Gating is therefore preset + unequal amounts,
  // never "the tiers descend": legacy buy-in and TOP3 races have always served
  // descending tiers and must keep the podium row they render today. An older
  // backend that omits `payoutPreset` or `payoutTiers` also falls through to
  // exactly today's rendering.

  /// Presets that pay a large slice of the field, where a decaying curve is
  /// worth a headline. TOP3/WINNER_TAKES_ALL already read fine as a podium.
  static const _gradedPayoutPresets = {'TOP_HALF', 'ALL_BUT_LAST'};

  /// Gated once, so both call sites (the prize-pool sheet and the inline
  /// race-info card) inherit the identical rule.
  ///
  /// Three conditions, all required:
  ///  1. a graded preset — TOP_HALF / ALL_BUT_LAST;
  ///  2. at least two tiers that are NOT all equal (an even split has its own
  ///     card, and a lone tier is a podium);
  ///  3. the race is APP-FUNDED — a `prizePool` object with `funded != false`.
  ///     Only funded seeded challenges are ever stamped with a curve. A legacy
  ///     buy-in race splits a real pot and can serve unequal graded tiers of
  ///     its own; those keep the podium row they have always rendered. An
  ///     absent or malformed `prizePool` (older backend, legacy race) reads as
  ///     not-funded via [RacePrizePool.fromRace]'s null, which is also the
  ///     safe degradation.
  bool _isGradedCurvePayout(List<PayoutTier> tiers) {
    if (tiers.length < 2) return false;
    if (!_gradedPayoutPresets.contains(_race?['payoutPreset'])) return false;
    if (_prizePool?.funded != true) return false;
    return tiers.any((t) => t.amount != tiers.first.amount);
  }

  /// The preset in plain words, mirroring [_evenSplitHeadline] — including its
  /// preset-agnostic fallback, so a future graded preset still reads correctly
  /// instead of rendering a blank headline.
  String _gradedHeadline(int paidPlaces) {
    switch (_race?['payoutPreset']) {
      case 'TOP_HALF':
        return 'Top half wins. Bigger prizes up top';
      case 'ALL_BUT_LAST':
        return 'Everyone but last wins. Bigger prizes up top';
      default:
        return 'The top $paidPlaces win. Bigger prizes up top';
    }
  }

  /// How many runners are actually in the race. Read defensively: a payload
  /// without a usable participant list yields 0, and the cut line then drops
  /// the "of N" half rather than printing "of 0".
  int get _acceptedFieldSize {
    // The true field, not the page: this drives the "of N" payout cut line.
    final summary = _summaryAcceptedCount;
    if (summary != null) return summary;
    final raw = _race?['participants'];
    if (raw is! List) return 0;
    return raw.where((p) => p is Map && p['status'] == 'ACCEPTED').length;
  }

  /// The viewer's current rank, preferring the SERVER's placement (contract §5
  /// C1) so this line agrees with home, the races list and the standings. Null
  /// when the viewer isn't running or there's nothing to rank yet — the "you"
  /// line is then omitted entirely.
  int? get _myViewerPlacement {
    final progress = _progressState.data ?? _progress;
    // Page projections keep the requester's authoritative placement at the
    // top level when their row is outside the visible page. Older/full
    // responses omit it, so retain the existing visible-row fallback.
    final projectedPlacement = _readNullableInt(progress?['myPlacement']);
    if (projectedPlacement != null && projectedPlacement > 0) {
      return projectedPlacement;
    }
    final raw = progress?['participants'];
    if (raw is! List) return null;
    final rows = raw
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
    if (rows.isEmpty) return null;
    final ordered = orderRaceParticipantsForDisplay(rows);
    final index = ordered.indexWhere(
      (p) => (p['userId'] as String?) == _myUserId,
    );
    if (index < 0) return null;
    return serverPlacementOf(ordered[index]) ?? index + 1;
  }

  Widget _buildPayoutSummary(
    List<PayoutTier> tiers, {
    required Key key,
    Color? labelColor,
    Color? amountColor,
  }) {
    final colors = AppColors.of(context);
    final label = labelColor ?? colors.textMid;
    final amount = amountColor ?? colors.coinDark;
    final paidPlaces = tiers.length;
    final perHead = tiers.first.amount;
    final fieldSize = _acceptedFieldSize;
    final placement = _myViewerPlacement;
    final inTheMoney = placement != null && placement <= paidPlaces;

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          _evenSplitHeadline(paidPlaces),
          textAlign: TextAlign.center,
          style: PixelText.body(size: 12.5, color: label),
        ),
        const SizedBox(height: 8),
        // The one number a runner is here for.
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '~${formatPrizeCoins(perHead)}',
              style: PixelText.number(size: 26, color: amount),
            ),
            const SizedBox(width: 6),
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                'coins each',
                style: PixelText.body(size: 12, color: label),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          fieldSize > 0
              ? 'Top $paidPlaces of $fieldSize get paid'
              : 'Top $paidPlaces get paid',
          textAlign: TextAlign.center,
          style: PixelText.body(size: 12, color: label),
        ),
        if (placement != null) ...[
          const SizedBox(height: 10),
          // Where the viewer stands relative to the cut — gold when the money
          // is theirs, quiet when it isn't. Both states derive from the same
          // tokens, so the night palette follows automatically.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: (inTheMoney ? amount : label).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: (inTheMoney ? amount : label).withValues(alpha: 0.4),
              ),
            ),
            child: Text(
              inTheMoney
                  ? 'You’re ${_lowerOrdinal(placement)}. In the money'
                  : 'You’re ${_lowerOrdinal(placement)}. '
                        '${placement - paidPlaces} '
                        '${placement - paidPlaces == 1 ? 'place' : 'places'} '
                        'from the cut',
              textAlign: TextAlign.center,
              style: PixelText.body(
                size: 12,
                color: inTheMoney ? amount : label,
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        GestureDetector(
          key: const Key('race-payout-see-all'),
          behavior: HitTestBehavior.opaque,
          onTap: () => _showPayoutBreakdownSheet(tiers),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'See all payouts',
                style: PixelText.title(size: 11, color: label),
              ),
              Icon(Icons.chevron_right, size: 14, color: label),
            ],
          ),
        ),
      ],
    );
  }

  /// The graded twin of [_buildPayoutSummary]: same four beats, same tokens,
  /// but the headline figure is 1st place rather than a per-head share.
  ///
  /// Every number is read off `payoutTiers` — the server owns the math. The
  /// 1st-place figure is explicitly labelled projected: the live projection
  /// sizes the pool from everyone accepted, settlement pays only walkers, and
  /// under a decaying curve that gap lands concentrated on the top spots.
  Widget _buildGradedPayoutSummary(
    List<PayoutTier> tiers, {
    required Key key,
    Color? labelColor,
    Color? amountColor,
  }) {
    final colors = AppColors.of(context);
    final label = labelColor ?? colors.textMid;
    final amount = amountColor ?? colors.coinDark;
    final paidPlaces = tiers.length;
    final topPrize = tiers.first.amount;
    final fieldSize = _acceptedFieldSize;
    final placement = _myViewerPlacement;
    final inTheMoney = placement != null && placement <= paidPlaces;

    // Match by placement rather than index: parsePayoutTiers drops zero-amount
    // tiers, so the list is not guaranteed to be a contiguous 1..N.
    int? myAmount;
    if (placement != null) {
      for (final tier in tiers) {
        if (tier.placement == placement) {
          myAmount = tier.amount;
          break;
        }
      }
    }

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          _gradedHeadline(paidPlaces),
          textAlign: TextAlign.center,
          style: PixelText.body(size: 12.5, color: label),
        ),
        const SizedBox(height: 8),
        // The number worth chasing.
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatPrizeCoins(topPrize),
              style: PixelText.number(size: 26, color: amount),
            ),
            const SizedBox(width: 6),
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                'coins for 1st',
                style: PixelText.body(size: 12, color: label),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Projected. Final payouts settle on who walked.',
          textAlign: TextAlign.center,
          style: PixelText.body(size: 11.5, color: label),
        ),
        const SizedBox(height: 4),
        Text(
          fieldSize > 0
              ? 'Top $paidPlaces of $fieldSize get paid'
              : 'Top $paidPlaces get paid',
          textAlign: TextAlign.center,
          style: PixelText.body(size: 12, color: label),
        ),
        if (placement != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: (inTheMoney ? amount : label).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: (inTheMoney ? amount : label).withValues(alpha: 0.4),
              ),
            ),
            child: Text(
              !inTheMoney
                  ? 'You’re ${_lowerOrdinal(placement)}. '
                        '${placement - paidPlaces} '
                        '${placement - paidPlaces == 1 ? 'place' : 'places'} '
                        'from the cut'
                  : myAmount != null
                  // What this rank is worth right now — the whole point of a
                  // curve is that the answer changes as you climb.
                  ? 'You’re ${_lowerOrdinal(placement)}. '
                        '${formatPrizeCoins(myAmount)} coins projected'
                  : 'You’re ${_lowerOrdinal(placement)}. In the money',
              textAlign: TextAlign.center,
              style: PixelText.body(
                size: 12,
                color: inTheMoney ? amount : label,
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        GestureDetector(
          key: const Key('race-graded-payout-see-all'),
          behavior: HitTestBehavior.opaque,
          onTap: () => _showPayoutBreakdownSheet(tiers),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'See all payouts',
                style: PixelText.title(size: 11, color: label),
              ),
              Icon(Icons.chevron_right, size: 14, color: label),
            ],
          ),
        ),
      ],
    );
  }

  /// "62nd", not "62ND" — this line is a sentence, not a scoreboard label.
  String _lowerOrdinal(int value) => formatOrdinal(value).toLowerCase();

  Widget _buildPayoutBreakdown(
    List<PayoutTier> tiers, {
    Key? key,
    Color? labelColor,
    Color? amountColor,
  }) {
    final resolvedLabelColor = labelColor ?? AppColors.of(context).textMid;
    final resolvedAmountColor = amountColor ?? AppColors.of(context).coinDark;
    final shown = tiers.take(3).toList();
    final extra = tiers.length - shown.length;
    return Row(
      key: key,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          _buildPayoutInlineValue(
            label: payoutPlacementLabel(shown[i].placement),
            amount: shown[i].amount,
            labelColor: resolvedLabelColor,
            amountColor: resolvedAmountColor,
          ),
        ],
        if (extra > 0) ...[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _showPayoutBreakdownSheet(tiers),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '+$extra MORE',
                  style: PixelText.title(size: 10, color: resolvedLabelColor),
                ),
                Icon(Icons.chevron_right, size: 12, color: resolvedLabelColor),
              ],
            ),
          ),
        ],
      ],
    );
  }

  void _showPayoutBreakdownSheet(List<PayoutTier> tiers) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.of(context).parchmentLight,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'PAYOUTS',
                  style: PixelText.title(
                    size: 14,
                    color: AppColors.of(context).textDark,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Flexible(
                  // A TOP_HALF Daily can pay 150 places. Build the rows lazily
                  // so the long case costs only what is on screen; short lists
                  // still wrap tightly instead of stretching the sheet.
                  child: ListView.builder(
                    shrinkWrap: tiers.length <= 12,
                    itemCount: tiers.length,
                    padding: EdgeInsets.zero,
                    itemBuilder: (context, index) {
                      final tier = tiers[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          children: [
                            Text(
                              payoutPlacementLabel(tier.placement),
                              style: PixelText.title(
                                size: 12,
                                color: AppColors.of(context).textMid,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${tier.amount}',
                              style: PixelText.number(
                                size: 14,
                                color: AppColors.of(context).coinDark,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPayoutInlineValue({
    required String label,
    required Object? amount,
    Color? labelColor,
    Color? amountColor,
  }) {
    final resolvedLabelColor = labelColor ?? AppColors.of(context).textMid;
    final resolvedAmountColor = amountColor ?? AppColors.of(context).coinDark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: PixelText.title(size: 10, color: resolvedLabelColor),
        ),
        const SizedBox(width: 3),
        Text(
          _formatCoinAmount(amount),
          style: PixelText.title(size: 10, color: resolvedAmountColor),
        ),
      ],
    );
  }

  Widget _buildParticipantRow(Map<String, dynamic> p) {
    final name = p['displayName'] as String? ?? '???';
    final status = p['status'] as String? ?? '';
    final userId = p['userId'] as String? ?? '';
    final profilePhotoUrl = p['profilePhotoUrl'] as String?;
    final isMe = userId == _myUserId;
    final isCreator = _race?['isCreator'] as bool? ?? false;
    final raceStatus = _race?['status'] as String? ?? '';
    final canKick =
        isCreator &&
        !isMe &&
        (raceStatus == 'PENDING' || raceStatus == 'ACTIVE');

    Color badgeColor;
    String badgeText;
    switch (status) {
      case 'ACCEPTED':
        badgeColor = AppColors.of(context).pillGreenDark;
        badgeText = 'JOINED';
      case 'DECLINED':
        badgeColor = AppColors.of(context).error;
        badgeText = 'DECLINED';
      default:
        badgeColor = AppColors.of(context).textMid;
        badgeText = 'INVITED';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          AppAvatar(
            name: name,
            imageUrl: profilePhotoUrl,
            size: 34,
            isUser: isMe,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isMe ? '${atName(name)} (you)' : atName(name),
              style: PixelText.body(
                size: 18,
                color: isMe
                    ? AppColors.of(context).textAccent
                    : AppColors.of(context).textDark,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: badgeColor,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              badgeText,
              style: PixelText.title(size: 12, color: Colors.white),
            ),
          ),
          if (canKick) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _confirmKick(userId, name),
              child: Padding(
                padding: EdgeInsets.all(4),
                child: Icon(
                  Icons.person_remove,
                  size: 18,
                  color: AppColors.of(context).error,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmKick(String userId, String displayName) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.of(context).parchment,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.person_remove,
                      size: 22,
                      color: AppColors.of(context).error,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Remove ${atName(displayName)}?',
                        style: PixelText.title(
                          size: 18,
                          color: AppColors.of(context).textDark,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'They will be removed from the race. Any held buy-in will be refunded.',
                  style: PixelText.body(
                    size: 13,
                    color: AppColors.of(context).textMid,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: PillButton(
                        label: 'CANCEL',
                        variant: PillButtonVariant.secondary,
                        fontSize: 13,
                        fullWidth: true,
                        onPressed: () => Navigator.of(ctx).pop(false),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: PillButton(
                        label: 'REMOVE',
                        variant: PillButtonVariant.accent,
                        fontSize: 13,
                        fullWidth: true,
                        onPressed: () => Navigator.of(ctx).pop(true),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (confirmed != true) return;

    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) return;

    try {
      await _api.kickRaceParticipant(
        identityToken: token,
        raceId: widget.raceId,
        userId: userId,
      );
      if (!mounted) return;
      await _loadDetails();
    } catch (e) {
      if (!mounted) return;
      showErrorToast(context, e.toString());
    }
  }

  /// Team total for the H2H banner: prefer the backend's honest team block
  /// (contract §7 — includes stealthed members' hidden steps, TR-658); fall
  /// back to summing visible planks when the block is absent.
  static int? _teamTotalFromProgress(
    Map<String, dynamic> progress,
    List<Map<String, dynamic>> participants,
    RaceTeam team,
  ) {
    final teams = progress['teams'];
    if (teams is Map) {
      final block = teams[team == RaceTeam.teamA ? 'teamA' : 'teamB'];
      if (block is Map) {
        final total = block['totalSteps'];
        if (total is num) return total.toInt();
      }
    }
    // F-16f: the old fallback summed the DISPLAYED planks via
    // TeamRace.teamTotal, which coerces a stealthed member's `totalSteps: null`
    // to 0 — silently undercounting that side while looking authoritative.
    // Null now means "unknown", and the banner shows a dash instead of a lie.
    return TeamRace.teamTotalOrNull(participants, team);
  }

  /// The side the VIEWER is on, or null when they aren't in this race (a
  /// spectator) — the lead banner uses it to choose between "you're ahead"
  /// phrasing and neutral third-person phrasing.
  RaceTeam? _myTeam(List<Map<String, dynamic>> participants) {
    // No explicit spectator guard: _isSpectator IS "no participant matches
    // _myUserId", so the loop below already falls through to null for them.
    for (final p in participants) {
      if (p['userId'] == _myUserId) return TeamRace.participantTeam(p);
    }
    return null;
  }

  /// TR-402/403/404: the settled team-race crown — winning team plaque with
  /// its members, or the dedicated tie state (all buy-ins refunded).
  Widget _buildTeamWinnerBoard(
    RaceTeam? winnerTeam,
    List<Map<String, dynamic>> participants,
  ) {
    if (winnerTeam == null) {
      return Column(
        children: [
          Icon(
            Icons.handshake_rounded,
            size: 44,
            color: AppColors.of(context).textMid,
          ),
          const SizedBox(height: 10),
          Text(
            'It\u2019s a tie. Buy-ins refunded',
            textAlign: TextAlign.center,
            style: PixelText.title(
              size: 16,
              color: AppColors.of(context).textDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Both teams finished dead even. Everyone got their coins back.',
            textAlign: TextAlign.center,
            style: PixelText.body(
              size: 12,
              color: AppColors.of(context).textMid,
            ),
          ),
        ],
      );
    }

    final members = TeamRace.membersOf(participants, winnerTeam);
    final color = TeamRace.color(winnerTeam, context);
    final colorLight = TeamRace.colorLight(winnerTeam, context);
    final colorDark = TeamRace.colorDark(winnerTeam, context);

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [colorLight, color],
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colorDark, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: colorDark,
                offset: const Offset(0, 3),
                blurRadius: 0,
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.emoji_events_rounded,
                size: 18,
                color: Colors.white,
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  TeamRace.teamName(_race!, winnerTeam).toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PixelText.title(size: 18, color: Colors.white)
                      .copyWith(
                        shadows: const [
                          Shadow(
                            color: Color(0x66000000),
                            offset: Offset(0, 1),
                            blurRadius: 0,
                          ),
                        ],
                      ),
                ),
              ),
            ],
          ),
        ),
        if (members.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 14,
            runSpacing: 10,
            children: [
              for (final m in members)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RacerAvatar(
                      rank: 1,
                      accessories:
                          (m['accessories'] as List?)
                              ?.cast<Map<String, dynamic>>() ??
                          const [],
                      size: 52,
                      ringColor: color,
                      animal: animalFromJson(m['animal']),
                    ),
                    const SizedBox(height: 5),
                    SizedBox(
                      width: 76,
                      child: Text(
                        atName(m['displayName'] as String? ?? '???'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: PixelText.body(
                          size: 11,
                          color: AppColors.of(context).textDark,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        const PlacementPill(placement: 1),
      ],
    );
  }

  /// TR-803: individual planks grouped by team under color/name headers.
  /// Plank rank stays the participant's OVERALL standing so the shield
  /// numbers still mean "place in the race".
  List<Widget> _buildTeamGroupedRows(List<Map<String, dynamic>> participants) {
    final rows = <Widget>[];
    for (final team in RaceTeam.values) {
      final sideLetter = team == RaceTeam.teamA ? 'A' : 'B';
      // Vertical separation between the two rosters (Issue 1).
      if (team == RaceTeam.teamB) {
        rows.add(const SizedBox(height: 16));
      }
      rows.add(
        _teamStandingsBanner(
          key: Key('team-group-$sideLetter'),
          team: team,
          memberCount: _sideMemberCount(participants, team),
        ),
      );
      rows.add(const SizedBox(height: 8));
      for (var i = 0; i < participants.length; i++) {
        if (TeamRace.participantTeam(participants[i]) == team) {
          rows.add(_buildLeaderboardPlank(participants[i], i, large: true));
        }
      }
    }
    // Defensive: a mismatched payload may carry team-less participants —
    // never drop anyone from the standings.
    final unassigned = [
      for (var i = 0; i < participants.length; i++)
        if (TeamRace.participantTeam(participants[i]) == null) i,
    ];
    for (final i in unassigned) {
      rows.add(_buildLeaderboardPlank(participants[i], i, large: true));
    }
    return rows;
  }

  int _sideMemberCount(List<Map<String, dynamic>> participants, RaceTeam team) {
    return participants
        .where((p) => TeamRace.participantTeam(p) == team)
        .length;
  }

  /// Issue 1: a bold, Clash-Royale-clear team header — a color plaque with the
  /// side name and its roster count — anchoring each roster in the standings.
  /// The prominent combined step totals live in the enlarged H2H banner
  /// directly above (kept there so the honest, stealth-safe totals aren't
  /// duplicated, TR-658). Stays on the parchment/wood identity via TeamColors.
  Widget _teamStandingsBanner({
    required Key key,
    required RaceTeam team,
    required int memberCount,
  }) {
    final color = TeamRace.color(team, context);
    final colorLight = TeamRace.colorLight(team, context);
    final colorDark = TeamRace.colorDark(team, context);
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [colorLight, color],
        ),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: colorDark, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: colorDark,
            offset: const Offset(0, 3),
            blurRadius: 0,
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            Icons.flag_rounded,
            size: 19,
            color: Colors.white.withValues(alpha: 0.95),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              TeamRace.teamName(_race ?? const {}, team).toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PixelText.title(size: 19, color: Colors.white).copyWith(
                shadows: const [
                  Shadow(
                    color: Color(0x66000000),
                    offset: Offset(0, 1.5),
                    blurRadius: 0,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: colorDark.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.groups_rounded,
                  size: 14,
                  color: Colors.white.withValues(alpha: 0.95),
                ),
                const SizedBox(width: 4),
                Text(
                  '$memberCount',
                  style: PixelText.number(size: 15, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The current front-runner of each team (highest steps), for the race-track

  Widget _buildTeamTwoColumns(
    List<Map<String, dynamic>> participants,
    ({TeamLaneState teamA, TeamLaneState teamB}) states,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _teamRosterColumn(participants, RaceTeam.teamA, states.teamA),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _teamRosterColumn(participants, RaceTeam.teamB, states.teamB),
        ),
      ],
    );
  }

  Widget _teamRosterColumn(
    List<Map<String, dynamic>> participants,
    RaceTeam team,
    TeamLaneState laneState,
  ) {
    final cells = <Widget>[];
    for (var i = 0; i < participants.length; i++) {
      if (TeamRace.participantTeam(participants[i]) != team) continue;
      if (cells.isNotEmpty) cells.add(const SizedBox(height: 8));
      cells.add(_teamColumnCell(participants[i], team, laneState));
    }
    if (cells.isEmpty) {
      cells.add(
        Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          alignment: Alignment.center,
          child: Text(
            'No one yet',
            // P8 (item 3) — the INVERSE bug: `textLight` is cream in BOTH
            // palettes, so on the LIGHT parchment card this was invisible.
            style: PixelText.body(
              size: 12.5,
              color: AppColors.of(context).textMid,
            ),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: cells,
    );
  }

  /// One racer in a team column: overall-rank shield, capy avatar, then a bold
  /// name + step count. Color-matched to its team; tapping a non-self,
  /// non-stealthed racer opens the friend-request sheet (parity with the plank).
  Widget _teamColumnCell(
    Map<String, dynamic> p,
    RaceTeam team,
    TeamLaneState laneState,
  ) {
    final name = p['displayName'] is String
        ? p['displayName'] as String
        : '???';
    final totalSteps = p['totalSteps'] is num
        ? (p['totalSteps'] as num).toInt()
        : 0;
    final userId = p['userId'] is String ? p['userId'] as String : '';
    final isMe = userId == _myUserId;
    final isStealthed = p['stealthed'] == true;
    final isForfeited = TeamRace.hasForfeited(p);
    final colorLight = TeamRace.colorLight(team, context);
    final colorDark = TeamRace.colorDark(team, context);
    final rawAccessories = p['accessories'];
    final accessories = isStealthed || rawAccessories is! List
        ? const <Map<String, dynamic>>[]
        : <Map<String, dynamic>>[
            for (final item in rawAccessories)
              if (item is Map<String, dynamic>) item,
          ];
    final animal = isStealthed ? null : animalFromJson(p['animal']);

    // Item 19: the multiplier chip existed only on the solo plank, so a
    // buffed/frozen/reversed racer looked untouched in the team scoreboard.
    // Same shared widget, same suppression rules; absent field → no chip.
    final multiplierChip = MultiplierChip.maybe(
      currentMultiplier: MultiplierChip.multiplierOf(p),
      isStealthed: isStealthed,
      compact: true,
    );
    final effects = isStealthed
        ? const <_EffectViewData>[]
        : _effectDataFor(userId);
    final displayName = isMe ? '${atName(name)} (you)' : atName(name);
    final palette = AppColors.of(context);
    final blend = switch (laneState) {
      TeamLaneState.leading => isMe ? 0.42 : 0.58,
      TeamLaneState.neutral => isMe ? 0.55 : 0.70,
      TeamLaneState.trailing => isMe ? 0.68 : 0.82,
    };
    final surface = team == RaceTeam.teamB
        ? Color.lerp(
            palette.parchmentLight,
            palette.roofRidge,
            laneState == TeamLaneState.leading ? 0.12 : 0.07,
          )!
        : Color.lerp(colorLight, palette.parchmentLight, blend)!;
    final isLeading = laneState == TeamLaneState.leading;

    Widget avatar() => SizedBox(
      key: ValueKey('team-avatar-$userId'),
      width: 30,
      height: 31,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          CapybaraSpriteWithAccessories(
            accessories: accessories,
            capybaraSize: 30,
            frameIndex: 0,
            animal: animal,
          ),
        ],
      ),
    );

    Widget nameText() => Text(
      displayName,
      key: ValueKey('team-name-$userId'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: PixelText.body(size: 11.5, color: palette.textDark),
    );

    Widget scoreGroup() {
      return Wrap(
        key: ValueKey('team-score-group-$userId'),
        spacing: 3,
        runSpacing: 1,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            _formatSteps(totalSteps),
            maxLines: 1,
            style: PixelText.number(
              size: 9.5,
              color: TeamRace.textColorOn(team, context),
            ),
          ),
          ?multiplierChip,
        ],
      );
    }

    final cell = Container(
      key: ValueKey('team-cell-$userId'),
      constraints: const BoxConstraints(minHeight: 59),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isLeading
              ? palette.medalGold
              : isMe
              ? colorDark
              : team == RaceTeam.teamB
              ? Color.lerp(palette.parchmentBorder, palette.roofRidge, 0.28)!
              : Color.lerp(colorDark, surface, 0.62)!,
          width: isLeading || isMe ? 2 : 1.25,
        ),
        boxShadow: isLeading
            ? [
                BoxShadow(
                  color: palette.medalGold.withValues(alpha: 0.20),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ]
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          avatar(),
          const SizedBox(width: 3),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: double.infinity, child: nameText()),
                const SizedBox(height: 2),
                MediaQuery.withClampedTextScaling(
                  // Give the compact stat line meaningful accessibility
                  // growth while keeping the exact value on one line inside
                  // a half-width team card. The username above remains fully
                  // responsive to the user's chosen scale.
                  maxScaleFactor: 1.3,
                  child: scoreGroup(),
                ),
              ],
            ),
          ),
          if (effects.isNotEmpty) ...[
            const SizedBox(width: 3),
            SizedBox(width: 44, child: _teamEffectTray(userId, effects)),
          ],
        ],
      ),
    );

    final presentedCell = isForfeited
        ? Opacity(opacity: 0.5, child: cell)
        : cell;

    if (isMe || isStealthed || userId.isEmpty) return presentedCell;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showFriendRequestSheet(
        context: context,
        authService: widget.authService,
        backendApiService: _api,
        userId: userId,
        displayName: name,
        profilePhotoUrl: p['profilePhotoUrl'] is String
            ? p['profilePhotoUrl'] as String
            : null,
      ),
      child: presentedCell,
    );
  }

  /// How many planks a collapsed standings board shows.
  static const int _kStandingsCollapsedRows = 8;

  /// Only collapse when there is meaningfully more roster than the collapsed
  /// view. A 9-runner race offering "show all 9" would be noise.
  static const int _kStandingsCollapseAbove = 10;

  /// Builds the solo standings board.
  ///
  /// A long roster collapses to [_kStandingsCollapsedRows] planks behind a
  /// "show all" row rather than scrolling inside a fixed window. The window
  /// version was worse UX: an inner scrollable wins the entire drag gesture, so
  /// reaching the last runner did NOT carry on into POWERUPS — the user had to
  /// lift off and re-drag outside the card. Collapsing keeps the page a single
  /// scroll surface and makes the long board opt-in.
  ///
  /// When the viewer's own plank falls below the cut it is pinned beneath the
  /// visible rows, because their own placement is the number they opened the
  /// race for.
  Future<void> _goToParticipantsPage(int offset) async {
    if (_participantsLoadingMore) return;
    final total = _participantsTotal;
    final clamped = offset < 0
        ? 0
        : (total != null && offset >= total)
        ? _participantsOffset
        : offset;
    if (clamped == _participantsOffset) return;
    _participantsOffset = clamped;
    await _loadProgress(append: true);
  }

  Widget _standingsList(
    List<Map<String, dynamic>> participants, {
    bool hasMore = false,
    bool isLoadingMore = false,
  }) {
    final rows = _buildLeaderboardRows(participants);
    // The local collapse exists for the UNPAGED board, where the server hands
    // back the entire field at once and 300 planks would bury the page. A
    // paged board is already exactly one page tall, so it gets the pager
    // instead — stacking both left two near-identical pills on top of each
    // other with counts that disagreed.
    final paginated = _participantsTotal != null;
    final collapsible = !paginated && rows.length > _kStandingsCollapseAbove;

    if (paginated) {
      final canGoBack = _participantsOffset > 0;
      final canGoForward = hasMore;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...rows,
          // The pager renders even on a single-page race so the position
          // readout ("1-12 of 12") is always available; both buttons simply
          // sit disabled.
          _standingsPagerRow(
            loadedCount: participants.length,
            isLoading: isLoadingMore,
            onPrevious: !canGoBack || isLoadingMore
                ? null
                : () {
                    unawaited(
                      _goToParticipantsPage(
                        _participantsOffset - _kParticipantsPageSize,
                      ),
                    );
                  },
            onNext: !canGoForward || isLoadingMore
                ? null
                : () {
                    unawaited(
                      _goToParticipantsPage(
                        _participantsOffset + participants.length,
                      ),
                    );
                  },
          ),
        ],
      );
    }

    if (!collapsible || _standingsExpanded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [...rows, if (collapsible) _standingsToggle(hiddenCount: 0)],
      );
    }

    final myIndex = participants.indexWhere(
      (p) => (p['userId'] as String?) == _myUserId,
    );
    final selfIsHidden = myIndex >= _kStandingsCollapsedRows;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...rows.take(_kStandingsCollapsedRows),
        if (selfIsHidden) ...[_standingsGapMarker(), rows[myIndex]],
        // Deliberately NO load-more row while collapsed. Two stacked "show N
        // more" controls read as a bug — one fetching the next page from the
        // server, one revealing planks already downloaded but hidden — and
        // their counts disagree (e.g. "SHOW 425 MORE" above "SHOW 12 MORE").
        // Collapsed, the only offer is to reveal what is already here, and the
        // toggle's count says exactly what its tap does; the page-fetch row
        // appears once expanded, when it is the only thing left to do.
        _standingsToggle(
          hiddenCount:
              rows.length - _kStandingsCollapsedRows - (selfIsHidden ? 1 : 0),
        ),
      ],
    );
  }

  /// PREV / NEXT pager beneath a paged standings board.
  ///
  /// The position readout sits ABOVE the buttons and states the window the
  /// board is actually showing ("26-50 of 446"). Each button then does one
  /// obvious thing, so neither has to carry a number that could disagree with
  /// what the tap delivers — the failure that made the old single "SHOW N
  /// MORE" control read as broken.
  Widget _standingsPagerRow({
    required int loadedCount,
    required VoidCallback? onPrevious,
    required VoidCallback? onNext,
    required bool isLoading,
  }) {
    final colors = AppColors.of(context);
    final total = _participantsTotal;
    final first = loadedCount == 0 ? 0 : _participantsOffset + 1;
    final last = _participantsOffset + loadedCount;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (total != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '$first-$last of $total',
                textAlign: TextAlign.center,
                style: PixelText.body(
                  size: 12,
                  color: colors.textDark.withValues(alpha: 0.6),
                ),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: PillButton(
                  key: const Key('standings-prev-page'),
                  label: 'PREV',
                  variant: PillButtonVariant.secondary,
                  fontSize: 13,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                  loading: isLoading,
                  onPressed: onPrevious,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PillButton(
                  key: const Key('standings-next-page'),
                  label: 'NEXT',
                  variant: PillButtonVariant.accent,
                  fontSize: 13,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                  loading: isLoading,
                  onPressed: onNext,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Marks the ranks skipped between the visible rows and the pinned self row,
  /// so the pinned plank doesn't read as though it follows 8th place.
  Widget _standingsGapMarker() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: Text(
          '• • •',
          style: PixelText.body(
            size: 13,
            color: AppColors.of(context).textDark.withValues(alpha: 0.45),
          ),
        ),
      ),
    );
  }

  /// The show-all / show-less control at the foot of a collapsible board.
  Widget _standingsToggle({required int hiddenCount}) {
    final colors = AppColors.of(context);
    final expanded = _standingsExpanded;
    final label = expanded ? 'SHOW LESS' : 'SHOW $hiddenCount MORE';

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: GestureDetector(
        key: const Key('standings-toggle'),
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _standingsExpanded = !expanded),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: colors.parchmentDark.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: colors.parchmentBorder.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: PixelText.body(
                  size: 14,
                  color: colors.textDark.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                size: 20,
                color: colors.textDark.withValues(alpha: 0.8),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildLeaderboardRows(List<Map<String, dynamic>> participants) {
    var finishedSeen = 0;
    final rows = <Widget>[];

    for (int i = 0; i < participants.length; i++) {
      final participant = participants[i];
      final finishPlace = participant['finishedAt'] != null
          ? ++finishedSeen
          : null;
      rows.add(
        _buildLeaderboardPlank(participant, i, finishPlace: finishPlace),
      );
    }

    return rows;
  }

  /// X-Ray recon sheet (item #2): shows every opponent's currently-active
  /// defenses from the DEFENSE_SCAN use response. [scan] is the response's
  /// `scan` object; null means an older backend consumed the item but returned
  /// no snapshot — degrade to a friendly "recon unavailable" state.
  Future<void> _showDefenseScanSheet(Map<String, dynamic>? scan) async {
    final opponents =
        (scan?['opponents'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.of(context).parchment,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.of(context).woodMid,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const PowerupIcon(type: 'DEFENSE_SCAN', size: 26),
                    const SizedBox(width: 8),
                    Text(
                      'X-RAY RECON',
                      style: PixelText.title(
                        size: 20,
                        color: AppColors.of(context).textDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  scan == null
                      ? 'Recon unavailable right now.'
                      : 'Active defenses across the field',
                  textAlign: TextAlign.center,
                  style: PixelText.body(
                    size: 12,
                    color: AppColors.of(context).textMid,
                  ),
                ),
                const SizedBox(height: 14),
                if (scan == null)
                  _reconEmptyState(
                    'This build could not read the scan. Try again later.',
                  )
                else if (opponents.isEmpty)
                  _reconEmptyState('No opponents to scan right now.')
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: opponents.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) =>
                          _reconOpponentRow(opponents[i]),
                    ),
                  ),
                const SizedBox(height: 16),
                PillButton(
                  label: 'Done',
                  icon: Icons.check_rounded,
                  fullWidth: true,
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _reconEmptyState(String message) {
    return GameContainer(
      padding: const EdgeInsets.all(16),
      frameColor: AppColors.of(context).parchmentBorder,
      child: Row(
        children: [
          Icon(
            Icons.radar_rounded,
            color: AppColors.of(context).textMid,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: PixelText.body(
                size: 13,
                color: AppColors.of(context).textMid,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reconOpponentRow(Map<String, dynamic> opponent) {
    final name = opponent['displayName'] as String? ?? '???';
    final defenses =
        (opponent['defenses'] as List?)?.cast<Map<String, dynamic>>() ??
        const [];
    return GameContainer(
      padding: const EdgeInsets.all(10),
      frameColor: defenses.isEmpty
          ? AppColors.of(context).parchmentBorder
          : AppColors.of(context).accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            atName(name),
            style: PixelText.title(
              size: 14,
              color: AppColors.of(context).textDark,
            ),
          ),
          const SizedBox(height: 6),
          if (defenses.isEmpty)
            Row(
              children: [
                Icon(
                  Icons.lock_open_rounded,
                  size: 16,
                  color: AppColors.of(context).pillGreen,
                ),
                const SizedBox(width: 6),
                Text(
                  'No defenses up. Safe to attack',
                  style: PixelText.body(
                    size: 12,
                    color: AppColors.of(context).textMid,
                  ),
                ),
              ],
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final d in defenses)
                  _reconDefenseChip(
                    d['type'] as String? ?? '',
                    d['expiresAt'] as String?,
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _reconDefenseChip(String type, String? expiresAt) {
    final remaining = _expiresInLabel(expiresAt);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.of(context).parchmentDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.of(context).parchmentBorder,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PowerupIcon(type: type, size: 18),
          const SizedBox(width: 6),
          Text(
            PowerupCopy.nameFor(type),
            style: PixelText.body(
              size: 12,
              color: AppColors.of(context).textDark,
            ),
          ),
          if (remaining != null) ...[
            const SizedBox(width: 6),
            Text(
              remaining,
              style: PixelText.body(
                size: 11,
                color: AppColors.of(context).textMid,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// "3h"/"12m"/"soon" remaining until [iso], or null when absent/past.
  String? _expiresInLabel(String? iso) {
    if (iso == null) return null;
    final dt = DateTime.tryParse(iso);
    if (dt == null) return null;
    final diff = dt.difference(DateTime.now());
    if (diff.isNegative) return null;
    if (diff.inMinutes < 1) return 'soon';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }

  /// Builds the compact status tray shown beside a solo standings name. The
  /// tray shows up to three framed sprites at once and scrolls horizontally
  /// when there are more; tapping opens the full participant status sheet.
  List<Widget> _effectIconsFor(String userId) {
    final effects = _effectDataFor(userId);
    if (effects.isEmpty) return const [];
    return [
      _ParticipantEffectTray(
        effects: effects,
        onTap: () => _showParticipantEffectsSheet(userId),
      ),
    ];
  }

  Future<void> _showParticipantEffectsSheet(String userId) async {
    final effects = _rawEffectsFor(userId);
    if (effects.isEmpty || !mounted) return;
    final classifier = _effectIsBoostForTarget(userId);
    final boosts = effects.where(classifier).toList();
    final debuffs = effects.where((e) => !classifier(e)).toList();
    final name = _displayNameForUser(userId) ?? 'Racer';

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.of(context).parchment,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.72,
      ),
      builder: (sheetContext) {
        final palette = AppColors.of(sheetContext);
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: palette.woodMid.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '${atName(name)} STATUS',
                  textAlign: TextAlign.center,
                  style: PixelText.title(size: 19, color: palette.textDark),
                ),
                const SizedBox(height: 4),
                Text(
                  '${effects.length} active '
                  '${effects.length == 1 ? 'effect' : 'effects'}',
                  textAlign: TextAlign.center,
                  style: PixelText.body(size: 12, color: palette.textMid),
                ),
                const SizedBox(height: 18),
                if (boosts.isNotEmpty)
                  _effectGroup(
                    label: 'BOOSTS',
                    icon: Icons.arrow_upward_rounded,
                    tint: palette.feedBoost,
                    effects: boosts,
                    isBoost: true,
                  ),
                if (boosts.isNotEmpty && debuffs.isNotEmpty)
                  const SizedBox(height: 12),
                if (debuffs.isNotEmpty)
                  _effectGroup(
                    label: 'DEBUFFS',
                    icon: Icons.arrow_downward_rounded,
                    tint: palette.feedAttack,
                    effects: debuffs,
                    isBoost: false,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool Function(Map<String, dynamic>) _effectIsBoostForTarget(
    String targetUserId,
  ) {
    return (effect) => effectIsBoost(
      type: effect['type'] is String ? effect['type'] as String : null,
      sourceUserId: effect['sourceUserId'] is String
          ? effect['sourceUserId'] as String
          : null,
      myUserId: targetUserId,
    );
  }

  /// Reads a mixed-version backend payload without assuming the list or any
  /// entry has the shape this build knows about.
  List<Map<String, dynamic>> _rawEffectsFor(String userId) {
    final raw = _powerupData?['activeEffects'];
    if (raw is! List) return const [];
    return [
      for (final effect in raw)
        if (effect is Map<String, dynamic> && effect['targetUserId'] == userId)
          effect,
    ];
  }

  /// Defensive effect view data shared by solo status and team trays. Entries
  /// without a non-empty type are individually ignored; optional source and
  /// expiry fields never make an otherwise valid effect disappear.
  List<_EffectViewData> _effectDataFor(String userId) {
    final effects = _rawEffectsFor(userId);
    return [
      for (final e in effects)
        if (e['type'] is String && (e['type'] as String).trim().isNotEmpty)
          _EffectViewData(
            type: e['type'] as String,
            attackerName:
                e['sourceUserId'] is String &&
                    (e['sourceUserId'] as String).isNotEmpty &&
                    e['sourceUserId'] != userId
                ? _displayNameForUser(e['sourceUserId'] as String)
                : null,
            isBoost: effectIsBoost(
              type: e['type'] as String,
              sourceUserId: e['sourceUserId'] is String
                  ? e['sourceUserId'] as String
                  : null,
              myUserId: userId,
            ),
            expiresAt: e['expiresAt'] is String
                ? e['expiresAt'] as String
                : null,
          ),
    ];
  }

  Widget _teamEffectTray(String userId, List<_EffectViewData> effects) {
    final names = effects.map((e) => PowerupCopy.nameFor(e.type)).join(', ');
    final platform = Theme.of(context).platform;
    final physics =
        platform == TargetPlatform.iOS || platform == TargetPlatform.macOS
        ? const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics())
        : const ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
    return LayoutBuilder(
      builder: (context, constraints) {
        const hitTarget = 44.0;
        const gap = 3.0;
        final contentWidth =
            (effects.length * hitTarget) +
            ((effects.length - 1).clamp(0, effects.length) * gap);
        final overflowing =
            effects.length > 1 &&
            constraints.maxWidth.isFinite &&
            contentWidth > constraints.maxWidth + 0.5;
        return Semantics(
          key: ValueKey('team-effect-tray-$userId'),
          label: overflowing
              ? '$names. Swipe horizontally for more effects.'
              : '$names active.',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: SizedBox(
              height: hitTarget,
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (bounds) => LinearGradient(
                  colors: overflowing
                      ? const [Colors.black, Colors.black, Colors.transparent]
                      : const [Colors.black, Colors.black, Colors.black],
                  stops: overflowing ? const [0, 0.88, 1] : const [0, 0.5, 1],
                ).createShader(bounds),
                child: SingleChildScrollView(
                  key: ValueKey('team-effect-scroll-$userId'),
                  primary: false,
                  scrollDirection: Axis.horizontal,
                  physics: physics,
                  child: Row(
                    children: [
                      for (var i = 0; i < effects.length; i++) ...[
                        if (i > 0) const SizedBox(width: gap),
                        _EffectIconWithTooltip(
                          key: ValueKey('team-effect-$userId-$i'),
                          effect: effects[i],
                          remainingLabel: _expiresInLabel(effects[i].expiresAt),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Resolves a participant's display name from a userId, for effect tooltips.
  /// Returns null when the id is absent or not found (defensive — the effect
  /// still renders, just without an attacker suffix).
  String? _displayNameForUser(String? userId) {
    if (userId == null || userId.isEmpty) return null;
    final rawParticipants = _progress?['participants'];
    if (rawParticipants is! List) return null;
    for (final p in rawParticipants) {
      if (p is Map<String, dynamic> && p['userId'] == userId) {
        return p['displayName'] is String ? p['displayName'] as String : null;
      }
    }
    return null;
  }

  Widget _buildLeaderboardPlank(
    Map<String, dynamic> p,
    int rank, {
    int? finishPlace,
    bool large = false,
  }) {
    // F-12e: the caller passes the array index; when the backend sent an
    // authoritative `placement` (1-based) that wins, so the number on screen is
    // the same one home and the races list show. Absent => the index, exactly
    // as before.
    final serverPlacement = serverPlacementOf(p);
    if (serverPlacement != null && serverPlacement > 0) {
      rank = serverPlacement - 1;
    }
    final name = p['displayName'] as String? ?? '???';
    final totalSteps = (p['totalSteps'] as num?)?.toInt() ?? 0;
    final userId = p['userId'] as String? ?? '';
    final isMe = userId == _myUserId;
    final isStealthed = p['stealthed'] == true;
    final isFinished = p['finishedAt'] != null;
    // Item 18: a stealthed row has no server placement (the backend masks it),
    // so the array index behind `rank` is meaningless for it. Show "?" rather
    // than a number that would collide with the visible rows' real ranks.
    final rankHidden = isStealthed && serverPlacement == null;
    // Additive backend field (item 6). Absent/null on older backends → no
    // multiplier badge.
    final currentMultiplier = (p['currentMultiplier'] as num?)?.toDouble();

    final plank = LeaderboardPlank(
      rank: rank,
      name: name,
      profilePhotoUrl: p['profilePhotoUrl'] as String?,
      steps: totalSteps,
      formattedSteps: _formatSteps(totalSteps),
      isUser: isMe,
      isStealthed: isStealthed,
      isFinished: isFinished,
      finishPlace: finishPlace,
      rankHidden: rankHidden,
      // Issue 1: team standings rows are larger for legibility; solo/ranked
      // keep the defaults.
      avatarSize: large ? 40 : 32,
      nameSize: large ? 17 : 15,
      stepsSize: large ? 18 : 16,
      verticalPadding: large ? 11 : 8,
      effectIcons: _effectIconsFor(userId),
      currentMultiplier: currentMultiplier,
    );

    // Tap a non-self, non-stealthed runner to open a friend-request sheet.
    if (isMe || isStealthed || userId.isEmpty) return plank;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showFriendRequestSheet(
        context: context,
        authService: widget.authService,
        backendApiService: _api,
        userId: userId,
        displayName: name,
        profilePhotoUrl: p['profilePhotoUrl'] as String?,
      ),
      child: plank,
    );
  }

  /// Returns a fake progress value for stealthed runners, jittered ±10%.
  /// Seeded by userId + current minute so it's stable within a minute but
  /// shifts each poll cycle.
  static double _jitterProgress(String userId) {
    final seed = userId.hashCode ^ (DateTime.now().minute * 7);
    final rng = math.Random(seed);
    final jitter = (rng.nextDouble() * 0.20) + 0.05; // 5%–25%
    return jitter.clamp(0.0, 1.0);
  }

  static String _formatSteps(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  /// Highest step count among all participants. Used as the "finish line"
  /// (1.0) so progress is measured relative to whoever is currently in front,
  /// which works whether or not the race has a fixed step target.
  static int _leaderSteps(List<Map<String, dynamic>> participants) {
    var max = 0;
    for (final p in participants) {
      final steps = (p['totalSteps'] as num?)?.toInt() ?? 0;
      if (steps > max) max = steps;
    }
    return max;
  }

  /// A runner's progress relative to the leader (0..1). If nobody has any
  /// steps yet (leaderSteps == 0) everyone sits at the start. Guards against
  /// division by zero and null/absent step fields from older backends.
  ///
  /// Used only for COMPLETED races, where "the winner sits on the finish
  /// line" is the correct final image. Live races use [_courseDenominator] —
  /// pure leader-relative pins whoever is ahead to the flag even at 100 steps.
  static double _leaderRelativeProgress(dynamic totalSteps, int leaderSteps) {
    if (leaderSteps <= 0) return 0.0;
    final steps = (totalSteps as num?)?.toInt() ?? 0;
    return (steps / leaderSteps).clamp(0.0, 1.0).toDouble();
  }

  /// Baseline daily pace the live track scales against — the app's canonical
  /// default step goal (see the backend's COMPAT_STEP_GOAL).
  static const int _baselineStepsPerDay = 5000;

  /// Denominator for live course positions:
  ///   max(leaderSteps, 5000/day × durationDays × max(elapsedFrac, 0.15))
  /// The time-scaled expectation keeps early-race positions sane (100 steps at
  /// minute one lands near the start, not the finish line); taking the max
  /// with leaderSteps guarantees a leader who outruns the expectation still
  /// caps at 1.0 instead of overflowing. The 0.15 floor avoids a near-zero
  /// denominator in the opening hours.
  double _courseDenominator(int leaderSteps) {
    final days = _readInt(_race?['maxDurationDays'], fallback: 7);
    final startedAt = DateTime.tryParse(_race?['startedAt'] as String? ?? '');
    final endsAt = DateTime.tryParse(_race?['endsAt'] as String? ?? '');
    var elapsedFrac = 1.0;
    if (startedAt != null && endsAt != null && endsAt.isAfter(startedAt)) {
      final total = endsAt.difference(startedAt).inSeconds;
      final elapsed = DateTime.now().difference(startedAt).inSeconds;
      elapsedFrac = (elapsed / total).clamp(0.0, 1.0).toDouble();
    }
    final expected = _baselineStepsPerDay * days * math.max(elapsedFrac, 0.15);
    final denom = math.max(leaderSteps.toDouble(), expected.toDouble());
    return denom > 0 ? denom : 1.0;
  }

  /// A runner's live course position (0..1) against [_courseDenominator].
  static double _courseProgress(dynamic totalSteps, double denominator) {
    if (denominator <= 0) return 0.0;
    final steps = (totalSteps as num?)?.toInt() ?? 0;
    return (steps / denominator).clamp(0.0, 1.0).toDouble();
  }

  /// Compact live countdown label ("2d 3h 14m", "3h 14m 05s", "14m 05s").
  static String _formatCountdownShort(Duration remaining) {
    final safe = remaining.isNegative ? Duration.zero : remaining;
    final days = safe.inDays;
    final hours = safe.inHours.remainder(24);
    final minutes = safe.inMinutes.remainder(60);
    final seconds = safe.inSeconds.remainder(60);
    if (days > 0) return '${days}d ${hours}h ${minutes}m';
    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds.toString().padLeft(2, '0')}s';
    }
    return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
  }
}

/// TR-802: the Start lever "glows/wiggles" once teams are even — an obvious,
/// looping arm pulse (scale + rotate) so the creator can't miss that it's go
/// time. Inert (and animation-free) while disarmed.
class _StartLeverPulse extends StatefulWidget {
  const _StartLeverPulse({required this.armed, required this.child});

  final bool armed;
  final Widget child;

  @override
  State<_StartLeverPulse> createState() => _StartLeverPulseState();
}

class _StartLeverPulseState extends State<_StartLeverPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    if (widget.armed) _controller.repeat();
  }

  @override
  void didUpdateWidget(_StartLeverPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.armed && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.armed && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.armed) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        // Two quick wiggles then a beat of rest each cycle.
        final burst = t < 0.45 ? math.sin(t / 0.45 * math.pi * 2) : 0.0;
        return Transform.rotate(
          angle: burst * 0.02,
          child: Transform.scale(scale: 1 + burst.abs() * 0.03, child: child),
        );
      },
      child: widget.child,
    );
  }
}

class _RaceProgressSkeleton extends StatelessWidget {
  const _RaceProgressSkeleton();

  @override
  Widget build(BuildContext context) {
    return LoadingSkeleton(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GameContainer(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SkeletonLine(width: 160, height: 18),
                const SizedBox(height: 14),
                Container(
                  height: 170,
                  decoration: BoxDecoration(
                    color: AppColors.of(
                      context,
                    ).parchmentDark.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.of(
                        context,
                      ).parchmentBorder.withValues(alpha: 0.45),
                    ),
                  ),
                  child: const Center(
                    child: SkeletonLine(width: 220, height: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const SkeletonLine(width: 190, height: 18),
          const SizedBox(height: 10),
          const ListSkeleton(itemCount: 3, showAvatar: true),
          const SizedBox(height: 14),
          const SkeletonLine(width: 150, height: 18),
          const SizedBox(height: 10),
          const GameContainer(
            padding: EdgeInsets.all(12),
            child: Row(
              children: [
                SkeletonBox(width: 46, height: 46, radius: 8),
                SizedBox(width: 10),
                Expanded(child: SkeletonLine(height: 12)),
                SizedBox(width: 10),
                SkeletonBox(width: 46, height: 46, radius: 8),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// Compact gold "Open All" pill for the POWERUPS header (item #1). Disabled
/// (greyed, non-tappable) while another powerup action is in flight.
/// Item 1 — the discard confirmation. Same wooden-sign chrome as the
/// delete-account confirm in Settings, so a destructive-with-payout action
/// looks like the other destructive action in the app.
class _DiscardConfirmDialog extends StatelessWidget {
  const _DiscardConfirmDialog({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      key: const Key('discard-confirm-dialog'),
      backgroundColor: Colors.transparent,
      child: TrailSign(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: PixelText.title(
                size: 18,
                color: AppColors.of(context).textDark,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              body,
              style: PixelText.body(
                size: 14,
                color: AppColors.of(context).textMid,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            PillButton(
              key: const Key('discard-confirm-yes'),
              label: 'DISCARD',
              variant: PillButtonVariant.accent,
              fullWidth: true,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              onPressed: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: 10),
            PillButton(
              key: const Key('discard-confirm-cancel'),
              label: 'CANCEL',
              variant: PillButtonVariant.secondary,
              fullWidth: true,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              onPressed: () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpenAllButton extends StatelessWidget {
  const _OpenAllButton({required this.onTap, this.loading = false});

  final VoidCallback? onTap;

  /// Item 12: the batch open is the slowest powerup action there is (one
  /// round trip plus the queued→inventory move), so it says so.
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !loading;
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(8),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.of(context).pillGold,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.of(context).pillGoldDark,
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.of(context).pillGoldShadow,
                  offset: Offset(2, 2),
                  blurRadius: 0,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (loading)
                  PillButtonSpinner(
                    size: 14,
                    color: AppColors.of(context).textDark,
                  )
                else
                  Icon(
                    Icons.auto_awesome_rounded,
                    size: 14,
                    color: AppColors.of(context).textDark,
                  ),
                const SizedBox(width: 4),
                Text(
                  loading ? 'OPENING…' : 'OPEN ALL',
                  style: PixelText.pill(
                    size: 11,
                    color: AppColors.of(context).textDark,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

@immutable
class _EffectViewData {
  const _EffectViewData({
    required this.type,
    required this.attackerName,
    required this.isBoost,
    required this.expiresAt,
  });

  final String type;
  final String? attackerName;
  final bool isBoost;
  final String? expiresAt;
}

/// Builds an overlay tooltip bubble anchored to [anchorContext]'s widget but
/// CLAMPED to the screen bounds (spec §4): pinned inside an 8pt margin on both
/// sides so a right-edge rail icon can't push it off-screen, capped at 200pt
/// wide, and flipped below the icon when there's no room above. Replaces the
/// old hardcoded `dx-60 / dy-68` offsets. The caller owns insert/remove.
OverlayEntry _buildClampedEffectTooltip({
  required BuildContext anchorContext,
  required Widget child,
  required VoidCallback onDismiss,
}) {
  const margin = 8.0;
  const estBubbleHeight = 96.0;
  final box = anchorContext.findRenderObject() as RenderBox;
  final overlayBox =
      Overlay.of(anchorContext).context.findRenderObject() as RenderBox;
  final anchorCenter = box.localToGlobal(
    box.size.center(Offset.zero),
    ancestor: overlayBox,
  );
  final overlaySize = overlayBox.size;
  final placeLeft = anchorCenter.dx <= overlaySize.width / 2;
  final topSafe =
      (MediaQuery.maybeOf(anchorContext)?.padding.top ?? 0) + margin;
  var top = anchorCenter.dy - box.size.height / 2 - estBubbleHeight;
  if (top < topSafe) {
    // Not enough room above: drop the bubble below the icon.
    top = anchorCenter.dy + box.size.height / 2 + 8;
  }

  return OverlayEntry(
    builder: (ctx) => GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: onDismiss,
      child: Stack(
        children: [
          Positioned(
            // Constraining to [margin, width - margin] guarantees the bubble is
            // always fully on-screen horizontally regardless of the icon's x.
            left: margin,
            right: margin,
            top: top,
            child: Align(
              alignment: placeLeft
                  ? Alignment.centerLeft
                  : Alignment.centerRight,
              child: Material(
                color: Colors.transparent,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 200),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.of(ctx).woodDark,
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black38,
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// A standings-row status tray beside the racer's name. Three readable,
/// polarity-framed sprites fit at once; additional effects continue in a
/// horizontal list. A narrow peek at the fourth tile advertises the swipe.
/// The tray remains one tap target for the full status sheet.
class _ParticipantEffectTray extends StatefulWidget {
  final List<_EffectViewData> effects;
  final VoidCallback onTap;

  const _ParticipantEffectTray({required this.effects, required this.onTap});

  @override
  State<_ParticipantEffectTray> createState() => _ParticipantEffectTrayState();
}

class _ParticipantEffectTrayState extends State<_ParticipantEffectTray> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isScrollable = widget.effects.length > 3;
    final visibleCount = math.min(widget.effects.length, 3);
    final trayWidth = isScrollable ? 103.0 : (visibleCount * 33.0) - 3;
    final names = widget.effects
        .map((e) => PowerupCopy.nameFor(e.type))
        .join(', ');

    return Semantics(
      key: const Key('participant-effect-tray'),
      label:
          '$names. ${isScrollable ? 'Swipe for more effects. ' : ''}'
          'Tap to view status.',
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.96 : 1,
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOut,
          child: SizedBox(
            width: trayWidth,
            height: 30,
            child: ListView.separated(
              key: const Key('participant-effect-scroll'),
              primary: false,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: widget.effects.length,
              separatorBuilder: (_, _) => const SizedBox(width: 3),
              itemBuilder: (context, index) =>
                  _EffectTrayPlate(effect: widget.effects[index]),
            ),
          ),
        ),
      ),
    );
  }
}

class _EffectTrayPlate extends StatelessWidget {
  final _EffectViewData effect;

  const _EffectTrayPlate({required this.effect});

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    final tint = effect.isBoost ? palette.feedBoost : palette.feedAttack;
    return Container(
      key: Key(
        'participant-effect-plate-${effect.isBoost ? 'boost' : 'debuff'}',
      ),
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: palette.isDark ? 0.25 : 0.14),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: tint.withValues(alpha: 0.72), width: 1),
        boxShadow: [
          BoxShadow(
            color: tint.withValues(alpha: 0.16),
            offset: const Offset(0, 1),
            blurRadius: 2,
          ),
        ],
      ),
      child: PowerupIcon(type: effect.type, size: 22),
    );
  }
}

class _EffectIconWithTooltip extends StatefulWidget {
  final _EffectViewData effect;
  final String? remainingLabel;

  const _EffectIconWithTooltip({
    super.key,
    required this.effect,
    required this.remainingLabel,
  });

  @override
  State<_EffectIconWithTooltip> createState() => _EffectIconWithTooltipState();
}

class _EffectIconWithTooltipState extends State<_EffectIconWithTooltip> {
  OverlayEntry? _entry;

  void _show() {
    _dismiss();
    final effect = widget.effect;
    final name = PowerupCopy.nameFor(effect.type);
    final parts = <String>[];
    final subtitle = PowerupCopy.effectRailSubtitleFor(effect.type);
    if (subtitle.isNotEmpty) parts.add(subtitle);
    final attacker = effect.attackerName;
    if (attacker != null && attacker.isNotEmpty) {
      parts.add('From ${atName(attacker)}');
    }
    final remaining = widget.remainingLabel;
    if (remaining != null) parts.add(remaining);
    final detail = parts.isEmpty ? name : '$name: ${parts.join('. ')}';

    _entry = _buildClampedEffectTooltip(
      anchorContext: context,
      onDismiss: _dismiss,
      child: Text(
        detail,
        style: PixelText.body(size: 11, color: AppColors.of(context).textLight),
      ),
    );
    Overlay.of(context).insert(_entry!);
    Future.delayed(const Duration(seconds: 3), _dismiss);
  }

  void _dismiss() {
    _entry?.remove();
    _entry = null;
  }

  @override
  void dispose() {
    _dismiss();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effect = widget.effect;
    final name = PowerupCopy.nameFor(effect.type);
    final palette = AppColors.of(context);
    final tint = effect.isBoost ? palette.feedBoost : palette.feedAttack;
    final icon = Container(
      key: Key('team-effect-plate-${effect.isBoost ? 'boost' : 'debuff'}'),
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: palette.isDark ? 0.25 : 0.14),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: tint.withValues(alpha: 0.72), width: 1),
        boxShadow: [
          BoxShadow(
            color: tint.withValues(alpha: 0.16),
            offset: const Offset(0, 1),
            blurRadius: 2,
          ),
        ],
      ),
      child: PowerupIcon(type: effect.type, size: 20),
    );

    return Semantics(
      label: name,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _show,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          child: Center(child: icon),
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final RaceChatMessage message;
  final bool isMine;
  final VoidCallback? onLongPress;

  const _ChatBubble({
    required this.message,
    required this.isMine,
    this.onLongPress,
  });

  String _formatTime(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    final ampm = t.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ampm';
  }

  @override
  Widget build(BuildContext context) {
    final bubbleColor = isMine
        ? AppColors.of(context).accent
        : AppColors.of(context).parchmentDark;
    final textColor = isMine
        ? AppColors.of(context).textLight
        : AppColors.of(context).textDark;
    final metaColor = isMine
        ? AppColors.of(context).textLight.withValues(alpha: 0.72)
        : AppColors.of(context).textMid.withValues(alpha: 0.8);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isMine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!isMine) ...[
            PlayerAvatar(
              name: message.senderName ?? '?',
              imageUrl: message.senderPhotoUrl,
              size: 28,
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: GestureDetector(
              onLongPress: onLongPress,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.of(context).textMid.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isMine && message.senderName != null)
                      Text(
                        atName(message.senderName!),
                        style: PixelText.title(
                          size: 12,
                          color: AppColors.of(context).textMid,
                        ),
                      ),
                    Text(
                      message.body,
                      style: PixelText.body(size: 16, color: textColor),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _formatTime(message.createdAt),
                          style: PixelText.body(size: 11, color: metaColor),
                        ),
                        if (message.pending) ...[
                          const SizedBox(width: 4),
                          Icon(Icons.access_time, size: 11, color: metaColor),
                        ],
                        if (message.failed) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.error_outline,
                            size: 11,
                            color: AppColors.of(context).feedAttack,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
