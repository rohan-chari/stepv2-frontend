import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/animals.dart';
import '../models/loadable.dart';
import '../models/race_payouts.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../services/notification_service.dart';
import '../services/race_chat_service.dart';
import '../services/race_feed_service.dart';
import '../styles.dart';
import '../utils/at_name.dart';
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
import '../widgets/spinning_coin.dart';
import '../widgets/coin_balance_badge.dart';
import '../widgets/spinning_crate.dart';
import '../widgets/game_container.dart';
import '../widgets/friend_request_sheet.dart';
import '../widgets/leaderboard_plank.dart';
import '../widgets/team_h2h_banner.dart';
import '../widgets/team_lobby_board.dart';
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

  /// Only set when this screen is rendered behind the onboarding tutorial's
  /// spotlight; anchors the "Powerups & boxes" callout to the inventory block.
  /// Null in the real app.
  final GlobalKey? tutorialPowerupsKey;

  RaceDetailScreen({
    super.key,
    required this.authService,
    required this.raceId,
    this.friends = const [],
    BackendApiService? backendApiService,
    this.notificationService,
    this.tutorialPowerupsKey,
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

// Powerup types hidden from this build's inventory/store surfaces even if a
// user still owns one. Currently only IMPOSTER, which is disabled server-side
// (item #3); the DB rows are left intact so re-enabling is a single flag flip.
const _hiddenPowerupTypes = {'IMPOSTER'};

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
    with WidgetsBindingObserver {
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
  int _queuedBoxCount = 0;
  // Globally-owned (coin-purchased) powerups, by type -> quantity. Spendable
  // into this race via the redeem flow. Loaded best-effort; an older backend
  // without the endpoint leaves this empty (no extra UI, no crash).
  Map<String, int> _globalPowerupInventory = const {};
  bool _isLoading = true;
  bool _isActing = false;
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
  late DateTime _countdownNow;

  // Activity/Chat tabs state.
  // 0 = Activity (system/powerup events, default), 1 = Chat (user messages).
  int _activityTabIndex = 0;

  // Chat tab (user messages).
  RaceChatService? _chat;
  bool _chatInitialized = false;
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
  Map<String, dynamic>? _starterReward;
  bool _starterRewardModalShown = false;
  bool _alertPermissionUndetermined = false;

  // Activity tab (system/powerup events).
  RaceFeedService? _feed;
  bool _feedInitialized = false;

  String get _myUserId => widget.authService.userId ?? '';
  BackendApiService get _api => widget.backendApiService;

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
    WidgetsBinding.instance.addObserver(this);
    _countdownNow = DateTime.now();
    _messageFocus.addListener(_onComposerFocusChanged);
    _loadDetails();
    if (widget.authService.onboardingV2Enabled) {
      _loadStarterReward();
      _loadAlertPermissionState();
    }
  }

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

  /// One dialog that carries the bonus end to end: it opens on the offer, and
  /// swaps in place to the claimed state rather than stacking a second modal
  /// on top of the first. `claiming` and `claimed` are local to this closure —
  /// the dialog owns them via StatefulBuilder, since a screen-level setState
  /// does not rebuild a route sitting above it.
  Future<void> _showStarterRewardModal() {
    final amount = (_starterReward?['amount'] as num?)?.toInt() ?? 100;
    var claiming = false;
    var claimed = false;

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.62),
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setModalState) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: GameContainer(
            padding: const EdgeInsets.all(28),
            frameColor: AppColors.accent,
            surfaceColor: AppColors.parchmentLight,
            glowColor: AppColors.coinMid,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SpinningCoin(size: 54),
                const SizedBox(height: 14),
                Text(
                  claimed ? '+$amount COINS' : 'FIRST RACE BONUS',
                  textAlign: TextAlign.center,
                  style: PixelText.title(
                    size: claimed ? 28 : 22,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  claimed
                      ? 'Starter reward claimed.'
                      : 'A little fuel for your Bara debut.',
                  textAlign: TextAlign.center,
                  style: PixelText.body(size: 14, color: AppColors.textMid),
                ),
                const SizedBox(height: 20),
                PillButton(
                  key: const Key('claim-starter-reward'),
                  label: claimed
                      ? 'LET’S RACE'
                      : claiming
                      ? 'CLAIMING...'
                      : 'CLAIM $amount COINS',
                  fullWidth: true,
                  onPressed: claiming
                      ? null
                      : claimed
                      ? () => Navigator.of(dialogContext).pop()
                      : () async {
                          setModalState(() => claiming = true);
                          final granted = await _claimStarterReward();
                          if (!dialogContext.mounted) return;
                          // A refused claim has already toasted (or is simply
                          // an old backend) — close rather than stranding the
                          // user on a button that will not resolve.
                          if (!granted) {
                            Navigator.of(dialogContext).pop();
                            return;
                          }
                          setModalState(() {
                            claiming = false;
                            claimed = true;
                          });
                        },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (racePollLifecycleAction(state, wasPolling: _pollingActive)) {
      case RacePollLifecycleAction.pause:
        // Off-screen: stop the network poll AND the 1s countdown ticker. The
        // ticker only drives UI (setState of _countdownNow), so ticking it
        // while backgrounded is wasted work; both are restarted on resume via
        // the flags below. The flags stay set so resume knows to restart.
        _pollTimer?.cancel();
        _countdownTimer?.cancel();
        break;
      case RacePollLifecycleAction.resume:
        // Foreground again after having polled: fetch once immediately for an
        // instant catch-up (the seq guard in _loadProgress keeps ordering
        // correct), then restart the periodic poll. _startPolling re-guards
        // its own timer.
        _loadProgress();
        _startPolling();
        break;
      case RacePollLifecycleAction.none:
        break;
    }
    // Restart the countdown ticker on any resume where it was running — covers
    // both ACTIVE races (which also resumed polling above) and PENDING
    // scheduled races (which tick a countdown but never poll).
    if (state == AppLifecycleState.resumed && _countdownActive) {
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
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    _messageInput.dispose();
    _messageFocus.dispose();
    final chat = _chat;
    if (chat != null) {
      chat.markRead();
      chat.dispose();
    }
    final feed = _feed;
    if (feed != null) {
      feed.dispose();
    }
    super.dispose();
  }

  void _ensureChatInitialized({bool poll = true}) {
    if (_chatInitialized) return;
    final race = _race;
    if (race == null) return;
    _chatInitialized = true;
    final chat = RaceChatService(
      authService: widget.authService,
      raceId: widget.raceId,
      api: widget.backendApiService,
    );
    chat.setMutedFromServer(race['myChatMuted'] as bool? ?? false);
    _chat = chat;
    chat.addListener(_onChatChanged);
    chat.loadInitial().then((_) {
      if (!mounted) return;
      // Initial chat load shouldn't count as unread; the user just opened the
      // race. Clear any unread set during load if we're already on Chat.
      if (_activityTabIndex == 1) {
        chat.markChatViewed();
      } else {
        chat.markRead();
      }
    });
    if (poll) chat.startPolling();
  }

  void _ensureFeedInitialized({bool poll = true}) {
    if (_feedInitialized) return;
    if (_race == null) return;
    _feedInitialized = true;
    final feed = RaceFeedService(
      authService: widget.authService,
      raceId: widget.raceId,
      api: widget.backendApiService,
    );
    _feed = feed;
    feed.addListener(_onFeedChanged);
    feed.loadInitial();
    if (poll) feed.startPolling();
  }

  void _onChatChanged() {
    if (!mounted) return;
    final chat = _chat;
    // New incoming messages arrived while the user is not on the Chat tab.
    if (chat != null && chat.hasUnread && _activityTabIndex != 1) {
      _chatHasUnread = true;
    }
    setState(() {});
  }

  void _onFeedChanged() {
    if (mounted) setState(() {});
  }

  void _onTabChanged(int index) {
    if (_activityTabIndex == index) return;
    setState(() => _activityTabIndex = index);
    if (index == 1) {
      // Switched to Chat: clear unread + persist read state on the server.
      _chatHasUnread = false;
      _chat?.markChatViewed();
    } else {
      // Switched away from Chat: persist read state.
      _chat?.markRead();
    }
  }

  Future<void> _loadDetails() async {
    try {
      final token = widget.authService.authToken;
      if (token == null || token.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // Fire progress alongside details instead of after it — the two are
      // independent and progress is the slower call, so this removes a full
      // serial round-trip from screen open. If the race turns out not to be
      // ACTIVE the prefetched result is simply discarded (errors included:
      // the catchError below keeps a non-ACTIVE race's progress fetch from
      // surfacing as an unhandled async error).
      final progressPrefetch = _api
          .fetchRaceProgress(identityToken: token, raceId: widget.raceId)
          .then((p) => p as Map<String, dynamic>?)
          .catchError((_) => null);

      final details = await _api.fetchRaceDetails(
        identityToken: token,
        raceId: widget.raceId,
      );

      if (!mounted) return;
      setState(() {
        _race = details;
        _isLoading = false;
        // One mute covers both placement and chat; treat the race as muted if
        // either flag is set. Defaults false for older backends missing the keys.
        _placementMuted =
            (details['myPlacementAlertsMuted'] as bool? ?? false) ||
            (details['myChatMuted'] as bool? ?? false);
      });

      if (details['status'] == 'ACTIVE') {
        _maybeShowStarterRewardModal();
        _loadProgress(prefetched: progressPrefetch);
        _startPolling();
        _startCountdown();
        _ensureChatInitialized();
        _ensureFeedInitialized();
      } else if (details['status'] == 'COMPLETED') {
        // Finished races keep their chat + activity viewable (read-only —
        // _canPostMessage is false and the backend rejects posts). Load once,
        // no polling: the conversation can't change anymore.
        _ensureChatInitialized(poll: false);
        _ensureFeedInitialized(poll: false);
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
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        showErrorToast(context, e.toString());
      }
    }
  }

  Future<void> _loadProgress({
    Future<Map<String, dynamic>?>? prefetched,
  }) async {
    // Ordering guard: concurrent fetches (30s poll vs the refresh fired right
    // after opening a box) can resolve out of order, and a stale snapshot
    // landing last used to overwrite the fresh one — an opened mystery box
    // would visibly "un-open" until the next poll. Only the newest-issued
    // request may commit its response.
    final fetchSeq = ++_progressFetchSeq;
    final previous = _progress;
    if (mounted) {
      setState(() {
        _progressState = previous == null
            ? const Loadable.loading()
            : Loadable.refreshing(previous);
      });
    }

    try {
      final token = widget.authService.authToken;
      if (token == null || token.isEmpty) {
        if (mounted) {
          setState(() {
            _progressState = Loadable.error('Not signed in.', data: previous);
          });
        }
        return;
      }

      // A prefetched result (fired in parallel with details) is used when it
      // succeeded; a failed prefetch falls back to a fresh request so errors
      // still surface through the normal path below.
      final progress =
          (prefetched != null ? await prefetched : null) ??
          await _api.fetchRaceProgress(
            identityToken: token,
            raceId: widget.raceId,
          );

      if (!mounted || fetchSeq != _progressFetchSeq) return;
      setState(() {
        _progress = progress;
        _powerupData = progress['powerupData'] as Map<String, dynamic>?;
        final rawEvent = progress['globalEvent'];
        _globalEvent = rawEvent is Map
            ? Map<String, dynamic>.from(rawEvent)
            : null;
        _progressState = Loadable.success(progress);
      });

      if (_powerupData?['enabled'] == true) {
        // Skip the chat/feed refresh on the FIRST progress load: it lands
        // right after loadInitial() fetched the same pages, so refreshing
        // again just duplicated both message requests. Later loads (30s poll,
        // powerup actions) refresh as before to pick up new events.
        if (previous != null) {
          _chat?.refreshTop();
          _feed?.refreshTop();
        }

        // Best-effort: load the user's GLOBAL powerup stash so they can spend a
        // coin-purchased powerup (e.g. Imposter) into this race.
        _loadGlobalPowerupInventory(token);

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
            '$newQueued mystery box${newQueued > 1 ? 'es' : ''} queued \u2014 inventory full',
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
    } catch (e) {
      // A stale request's failure must not clobber a newer request's result.
      if (!mounted || fetchSeq != _progressFetchSeq) return;
      setState(() {
        _progressState = Loadable.error(e.toString(), data: previous);
      });
      if (previous != null) {
        showErrorToast(context, 'Couldn’t refresh race progress.');
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
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _loadProgress();
    });
  }

  void _startCountdown() {
    _countdownActive = true;
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _countdownNow = DateTime.now());
    });
  }

  Future<bool> _confirmPaidInvite({required bool activeRace}) async {
    final buyInAmount = _readInt(_race?['buyInAmount'], fallback: 0);
    if (buyInAmount <= 0) {
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
                style: PixelText.title(size: 18, color: AppColors.textDark),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                activeRace
                    ? 'Your $buyInAmount gold goes straight into the live pot.'
                    : 'Your $buyInAmount gold will be held until the race starts.',
                style: PixelText.body(size: 14, color: AppColors.textMid),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                activeRace
                    ? 'This race is already underway. You will need to catch up when you join.'
                    : 'You can only get this gold back if the race is cancelled.',
                style: PixelText.body(size: 13, color: AppColors.textMid),
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
    setState(() => _isActing = true);
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
    } catch (e) {
      if (mounted) showErrorToast(context, e.toString());
    } finally {
      if (mounted) setState(() => _isActing = false);
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
    final participants =
        (race['participants'] as List?)?.cast<Map<String, dynamic>>() ??
        const <Map<String, dynamic>>[];
    final accepted = participants
        .where((p) => p['status'] == 'ACCEPTED')
        .toList();
    final a = accepted
        .where((p) => TeamRace.participantTeam(p) == RaceTeam.teamA)
        .length;
    final b = accepted
        .where((p) => TeamRace.participantTeam(p) == RaceTeam.teamB)
        .length;
    return a >= size && b >= size;
  }

  RaceTeam? _myLobbyTeam() {
    final participants =
        (_race?['participants'] as List?)?.cast<Map<String, dynamic>>() ??
        const [];
    for (final p in participants) {
      if (p['userId'] == _myUserId) return TeamRace.participantTeam(p);
    }
    return null;
  }

  /// TR-601: mid-race forfeit for a team race. Permanent and consequential, so
  /// the dialog states all three outcomes plainly before anything happens:
  /// steps freeze but STAY with the team, no refund, no rejoin.
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
                style: PixelText.title(size: 18, color: AppColors.textDark),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              _forfeitConsequence(
                Icons.ac_unit_rounded,
                'Your steps freeze now and stay with $teamName — they still '
                'count toward the team total.',
              ),
              const SizedBox(height: 10),
              _forfeitConsequence(
                Icons.money_off_rounded,
                'No refund. Your buy-in stays in the pot, and you get no cut '
                'even if your team wins.',
              ),
              const SizedBox(height: 10),
              _forfeitConsequence(
                Icons.block_rounded,
                "This is permanent — you can't rejoin this race.",
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
      // A forfeit can settle the race outright (team collapse, TR-603) — a
      // full reload lets the screen fall into whatever state it's now in.
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

  Widget _forfeitConsequence(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.textMid),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: PixelText.body(size: 12.5, color: AppColors.textMid),
          ),
        ),
      ],
    );
  }

  /// TR-205: leaving a PENDING team lobby is free (hold released, rejoin ok).
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
                style: PixelText.title(size: 18, color: AppColors.textDark),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Your buy-in hold is released and your peg opens up. '
                'You can rejoin any time before the race starts.',
                style: PixelText.body(size: 14, color: AppColors.textMid),
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
                style: PixelText.title(size: 18, color: AppColors.textDark),
              ),
              const SizedBox(height: 12),
              Text(
                'This cannot be undone. Are you sure you want to cancel this race?',
                style: PixelText.body(size: 14, color: AppColors.textMid),
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

    final participants =
        (_race?['participants'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final existingIds = participants.map((p) => p['userId'] as String).toSet();

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
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) return;

    String? targetUserId;
    String? targetDirection;

    final participants =
        (_progress?['participants'] as List?)?.cast<Map<String, dynamic>>() ??
        [];
    // TR-651/657: enemy-team members only (no friendly fire) and no
    // forfeiters — an invalid target is never presented. Individual races keep
    // today's "everyone but me, minus stealthed" pool.
    final targets = TeamRace.offensiveTargets(
      participants: participants,
      myUserId: _myUserId,
      race: _race ?? const {},
    );

    if (type == 'PINECONE_TOSS') {
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
      final result = await _api.usePowerup(
        identityToken: token,
        raceId: widget.raceId,
        powerupId: powerup['id'] as String,
        targetUserId: targetUserId,
        targetDirection: targetDirection,
        targetEffectId: targetEffectId,
        upgradeLevel: upgradeLevel,
      );

      final res = result['result'] as Map<String, dynamic>?;
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
      if (type == 'DEFENSE_SCAN') {
        // X-Ray is an instantaneous intel read: the reveal rides back on the
        // use response as `scan` (contract puts it top-level; also check the
        // nested result for backend variance). Degrade safely if it's absent
        // (older backend that consumed the item but returns no snapshot).
        final scan =
            (result['scan'] as Map<String, dynamic>?) ??
            (res?['scan'] as Map<String, dynamic>?);
        await _showDefenseScanSheet(scan);
      } else if (outcome == AttackOutcome.blocked ||
          outcome == AttackOutcome.reflected) {
        await showAttackOutcomeModal(context, res ?? const {});
      } else if (type == 'SNEAKY_SWAP') {
        // Reveal what was stolen. Additive field — older backends (mutual
        // swap) return no stolenPowerup, so fall back to the generic toast.
        final stolen = res?['stolenPowerup'] as Map<String, dynamic>?;
        final stolenType = stolen?['type'] as String?;
        showInfoToast(
          context,
          stolenType != null
              ? 'You stole a ${PowerupCopy.nameFor(stolenType)}!'
              : '${PowerupCopy.nameFor(type)} activated!',
        );
      } else {
        final tierTag = upgradeLevel > 0 ? ' (Lvl $upgradeLevel)' : '';
        showInfoToast(
          context,
          '${PowerupCopy.nameFor(type)}$tierTag activated!',
        );
      }

      if (!mounted) return;
      _loadProgress();
    } catch (e) {
      restoreInventory();
      if (mounted) showErrorToast(context, e.toString());
    } finally {
      if (mounted) setState(() => _isActing = false);
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
      final items =
          (result['items'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      final inventory = <String, int>{};
      for (final row in items) {
        final type = row['powerupType'] as String?;
        final qty = (row['quantity'] as num?)?.toInt() ?? 0;
        if (type != null && qty > 0) inventory[type] = qty;
      }
      if (mounted) {
        setState(() => _globalPowerupInventory = inventory);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _globalPowerupInventory = const {});
      }
    }
  }

  /// Spends a globally-owned powerup (e.g. Imposter) into this race: redeems it
  /// to a HELD in-race powerup, then immediately runs the normal use flow
  /// (target picker etc.) on it. Reuses [_usePowerup] so targeting/feedback are
  /// identical to box-earned powerups.
  Future<void> _redeemAndUsePowerup(String powerupType) async {
    if (_isActing) return;
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) return;

    setState(() => _isActing = true);
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
      if (mounted) showErrorToast(context, e.toString());
      if (mounted) setState(() => _isActing = false);
      return;
    } finally {
      // Release the acting lock before _usePowerup re-acquires it.
      if (mounted) setState(() => _isActing = false);
    }

    if (redeemedPowerup == null) {
      // Redeem succeeded but no powerup returned — refresh so it shows in the
      // tray and the user can use it manually.
      _loadProgress();
      return;
    }

    // Run the normal use flow (target picker + use endpoint) on the redeemed
    // HELD powerup.
    await _usePowerup(redeemedPowerup);
  }

  Future<void> _discardPowerup(Map<String, dynamic> powerup) async {
    setState(() => _isActing = true);
    try {
      final token = widget.authService.authToken;
      if (token == null || token.isEmpty) return;

      await _api.discardPowerup(
        identityToken: token,
        raceId: widget.raceId,
        powerupId: powerup['id'] as String,
      );

      if (mounted) {
        showInfoToast(
          context,
          '${PowerupCopy.nameFor(powerup['type'] as String?)} discarded',
        );
        _loadProgress();
      }
    } catch (e) {
      if (mounted) showErrorToast(context, e.toString());
    } finally {
      if (mounted) setState(() => _isActing = false);
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
      backgroundColor: AppColors.parchment,
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
                            color: AppColors.textDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'CHOOSE A TARGET',
                      style: PixelText.title(
                        size: 12,
                        color: AppColors.textMid,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(height: 2, color: AppColors.parchmentDark),
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
                      onTap: () =>
                          Navigator.of(ctx).pop(t['userId'] as String?),
                      child: Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.parchmentDark,
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
                                  color: AppColors.textDark,
                                ),
                              ),
                            ),
                            if (t['totalSteps'] != null)
                              Text(
                                '${_formatSteps((t['totalSteps'] as num).toInt())} steps',
                                style: PixelText.number(
                                  size: 12,
                                  color: AppColors.textMid,
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
                    Container(height: 2, color: AppColors.parchmentDark),
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

  Future<String?> _showPineconeDirectionPicker() async {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.parchment,
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
                  style: PixelText.title(size: 16, color: AppColors.textMid),
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
  void _showPocketWatchSheet(
    Map<String, dynamic> powerup,
    String rarity,
    List<String>? tierLabels,
    int myCoins,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.parchment,
      isScrollControlled: true,
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
              _usePowerup(
                powerup,
                upgradeLevel: level,
                targetEffectId: targetEffectId,
              );
            },
          ),
        );
      },
    );
  }

  void _showPowerupActions(Map<String, dynamic> powerup) {
    final type = powerup['type'] as String;
    final rarity = (powerup['rarity'] as String?) ?? 'COMMON';
    final upgradeable = _isUpgradeable(type);
    final tierLabels = PowerupCopy.upgradeTierLabelsFor(type);
    final myCoins = widget.authService.coins;

    // §6.4: Pocket Watch gets its own two-mode sheet. The generic tier sheet
    // can't express "extend all my buffs" vs "extend ONE debuff I put on a
    // rival" — and picking wrong costs coins.
    if (type == 'POCKET_WATCH') {
      _showPocketWatchSheet(powerup, rarity, tierLabels, myCoins);
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.parchment,
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
                            color: AppColors.textDark,
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
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _rarityColors[rarity] ?? AppColors.textMid,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    rarity,
                    style: PixelText.title(size: 9, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  PowerupCopy.descriptionFor(type),
                  style: PixelText.body(size: 13, color: AppColors.textMid),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),

                // Tier options for upgradeable powerups; single USE button otherwise.
                if (upgradeable && tierLabels != null)
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
                  onPressed: _isActing
                      ? null
                      : () {
                          Navigator.of(ctx).pop();
                          _discardPowerup(powerup);
                        },
                ),
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
          ? 'USE BASE — ${tierLabels[0]}'
          : 'LVL $level — ${tierLabels[level]}';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Checkered arcade green — the same below-the-fold surface as the tabs,
      // so pushing into a race no longer flips back to the old parchment look.
      body: Stack(
        children: [
          const Positioned.fill(
            child: ColoredBox(
              color: AppColors.roofLight,
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
                  decoration: const BoxDecoration(
                    // Opaque, so scrolled content can't show through the fixed
                    // header (guarded by race_detail_screen_header_test).
                    color: AppColors.roofLight,
                    border: Border(
                      bottom: BorderSide(color: AppColors.roofDark, width: 1),
                    ),
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(true),
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(
                            Icons.arrow_back,
                            color: AppColors.parchment,
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
                          style: PixelText.title(
                            size: 22,
                            color: AppColors.parchment,
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
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.parchment,
                                    ),
                                  )
                                : const Icon(
                                    Icons.ios_share,
                                    color: AppColors.parchment,
                                    size: 24,
                                  ),
                          ),
                        ),
                      if (_canMutePlacementAlerts())
                        GestureDetector(
                          onTap: _togglingPlacementMute
                              ? null
                              : _togglePlacementMute,
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Icon(
                              _placementMuted
                                  ? Icons.notifications_off
                                  : Icons.notifications_active,
                              color: AppColors.parchment,
                              size: 24,
                            ),
                          ),
                        ),
                      // A matchup race (tournamentId set) is owned by the
                      // tournament engine — edit/cancel are locked server-side
                      // (TOURNAMENT_RACE_LOCKED), so hide the options entry
                      // entirely (spec §6.5/§9).
                      if (_race != null &&
                          _race!['tournamentId'] == null &&
                          (_race!['isCreator'] as bool? ?? false) &&
                          (_race!['status'] == 'PENDING' ||
                              _race!['status'] == 'ACTIVE'))
                        GestureDetector(
                          onTap: _showRaceOptionsSheet,
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(
                              Icons.more_horiz,
                              color: AppColors.parchment,
                              size: 24,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                Expanded(
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.accent,
                          ),
                        )
                      : _race == null
                      ? Center(
                          child: Text(
                            'Failed to load race',
                            style: PixelText.body(
                              size: 14,
                              color: AppColors.parchment,
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadDetails,
                          color: AppColors.accent,
                          backgroundColor: AppColors.parchment,
                          child: SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: EdgeInsets.zero,
                            child: _buildContent(),
                          ),
                        ),
                ),
                // Anchored bottom banner, in-flow below the scrollable so it
                // reserves its own space. SafeArea above excludes the bottom, so
                // the slot pads itself clear of the home indicator when an ad is
                // showing; it collapses to zero size otherwise, and also while
                // the keyboard is open so it can't cover the chat composer.
                const AdBannerSlot(
                  withBottomSafeArea: true,
                  hideWhenKeyboardOpen: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
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
        status == 'ACTIVE' &&
        _race?['myStatus'] == 'ACCEPTED' &&
        widget.authService.onboardingV2Enabled &&
        _alertPermissionUndetermined;
    if (showAlerts) {
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

  static const _raceDayAsset = 'assets/images/race_day_course.png';

  Widget _buildRaceHero({
    required List<GoalTrackRunner> runners,
    List<Widget> chips = const [],
  }) {
    // TR-901: the goal-line/milestone marker is gone with target-steps races;
    // the hero course is purely leader-relative now.
    return Stack(
      children: [
        HomeCourseTrack(
          height: 286,
          backdropAsset: _raceDayAsset,
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
        color: HomeColors.ink.withValues(alpha: 0.9),
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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer_rounded, size: 16, color: AppColors.pillGold),
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

  /// Prize-pool chip — tapping opens the payout breakdown sheet.
  Widget _prizeChip() {
    final potCoins = _readInt(_race!['projectedPotCoins'], fallback: 0);
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
                '$potCoins',
                style: PixelText.title(size: 15, color: AppColors.pillGold),
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

  /// Bottom sheet with the pot and the full payout breakdown (podium +
  /// "+N MORE" expansion, same as before — just summoned from the hero chip).
  void _showPrizePoolSheet() {
    final potCoins = _readInt(_race!['projectedPotCoins'], fallback: 0);
    final payoutTiers = parsePayoutTiers(_race);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.parchmentLight,
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
                    color: AppColors.woodMid,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'PRIZE POOL',
                  style: PixelText.title(size: 16, color: AppColors.textMid),
                ),
                const SizedBox(height: 4),
                Text(
                  '$potCoins',
                  style: PixelText.number(size: 40, color: AppColors.coinDark),
                ),
                Text(
                  'gold',
                  style: PixelText.body(size: 13, color: AppColors.textMid),
                ),
                if (payoutTiers.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: _buildPayoutBreakdown(
                      payoutTiers,
                      key: const Key('race-prize-pool-summary'),
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
              color: AppColors.pillGold,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: AppColors.pillGoldDark),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: PixelText.title(
                size: 16,
                color: AppColors.parchment,
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
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(14),
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        width: double.infinity,
        padding: padding,
        decoration: raceCardDecoration(),
        child: child,
      ),
    );
  }

  Widget _buildRaceInfoCard() {
    final maxDays = _readInt(_race!['maxDurationDays'], fallback: 7);
    final buyInAmount = _readInt(_race!['buyInAmount'], fallback: 0);
    final potCoins = _readInt(_race!['projectedPotCoins'], fallback: 0);
    final payoutTiers = parsePayoutTiers(_race);

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
            if (buyInAmount > 0) ...[
              Expanded(
                child: StatColumn(
                  label: 'BUY-IN',
                  value: '$buyInAmount',
                  alignment: CrossAxisAlignment.center,
                  valueColor: AppColors.coinDark,
                ),
              ),
              Expanded(
                child: StatColumn(
                  label: 'POT',
                  value: '$potCoins',
                  alignment: CrossAxisAlignment.center,
                  valueColor: AppColors.coinDark,
                ),
              ),
            ],
          ],
        ),
        if (buyInAmount > 0 && payoutTiers.isNotEmpty) ...[
          const SizedBox(height: 10),
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
    final isSeeded = (_race!['seedKind'] as String?) != null;
    final isTeamRace = TeamRace.isTeamRace(_race!);
    final participants =
        (_race!['participants'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final acceptedCount = participants
        .where((p) => p['status'] == 'ACCEPTED')
        .length;

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
      for (final p in participants)
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
                    const Icon(
                      Icons.flag_rounded,
                      size: 16,
                      color: AppColors.pillGold,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'AT THE START LINE',
                      style: PixelText.title(size: 13, color: Colors.white),
                    ),
                  ],
                ),
              ),
            const Spacer(),
            if (_readInt(_race!['buyInAmount'], fallback: 0) > 0) _prizeChip(),
          ],
        ),
        const SizedBox(height: 16),

        _checkerSectionHeader('RACE DETAILS'),
        _sectionCard(child: _buildRaceInfoCard()),
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
                  onTapEmptySlot: (_isActing || myStatus == 'DECLINED')
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
                      color: AppColors.parchmentDark,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.parchmentBorder,
                        width: 2,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.hourglass_top_rounded,
                          size: 18,
                          color: AppColors.textMid.withValues(alpha: 0.8),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Both teams are full — someone beat you to it! '
                            'Your invite stays put: if a spot frees up, hop '
                            'straight in.',
                            style: PixelText.body(
                              size: 12.5,
                              color: AppColors.textMid,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (myStatus == 'INVITED') ...[
                  const SizedBox(height: 12),
                  Text(
                    'Tap an empty peg to pick your side and join!',
                    textAlign: TextAlign.center,
                    style: PixelText.body(size: 13, color: AppColors.textMid),
                  ),
                ] else if (myStatus == 'ACCEPTED') ...[
                  const SizedBox(height: 12),
                  Text(
                    'Tap an empty peg on the other side to switch teams',
                    textAlign: TextAlign.center,
                    style: PixelText.body(size: 12, color: AppColors.textMid),
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
              background: AppColors.parchmentDark,
              foreground: AppColors.textMid,
              fontSize: 12,
            ),
          ),
          _sectionCard(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [for (final p in participants) _buildParticipantRow(p)],
            ),
          ),
        ],
        const SizedBox(height: 16),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: _buildPendingActions(
            isCreator: isCreator,
            myStatus: myStatus,
            isSeeded: isSeeded,
            acceptedCount: acceptedCount,
            scheduledInFuture: scheduledInFuture,
            scheduledStartAt: scheduledStartAt,
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildPendingActions({
    required bool isCreator,
    required String myStatus,
    required bool isSeeded,
    required int acceptedCount,
    required bool scheduledInFuture,
    required DateTime? scheduledStartAt,
  }) {
    // TR-301 gating for team races: both sides equal and nonzero. The lever
    // stays visibly disabled with live "Teams must be even — 2v1" copy.
    final isTeamRace = TeamRace.isTeamRace(_race ?? const {});
    final participants =
        (_race?['participants'] as List?)?.cast<Map<String, dynamic>>() ??
        const <Map<String, dynamic>>[];
    final accepted = participants
        .where((p) => p['status'] == 'ACCEPTED')
        .toList();
    final teamACount = accepted
        .where((p) => TeamRace.participantTeam(p) == RaceTeam.teamA)
        .length;
    final teamBCount = accepted
        .where((p) => TeamRace.participantTeam(p) == RaceTeam.teamB)
        .length;
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
                const Icon(
                  Icons.pause_circle_filled_rounded,
                  size: 18,
                  color: AppColors.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'START PAUSED — WAITING FOR EVEN TEAMS',
                        style: PixelText.title(
                          size: 12,
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        teamACount == 0 || teamBCount == 0
                            ? "Both teams need at least 1 racer. We'll start "
                                  'it automatically as soon as they even up.'
                            : "It's ${teamACount}v$teamBCount right now — "
                                  "we'll start it automatically as soon as "
                                  'the teams are even.',
                        style: PixelText.body(
                          size: 12,
                          color: AppColors.textMid,
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
                Icon(Icons.schedule, size: 18, color: AppColors.pillGreenDark),
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
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'at ${_formatScheduledStart(scheduledStartAt)}',
                        style: PixelText.body(
                          size: 12,
                          color: AppColors.textMid,
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

        // Actions
        if (isCreator) ...[
          if (!scheduledInFuture) ...[
            RetroCard(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              child: Row(
                children: [
                  Icon(
                    Icons.groups_rounded,
                    size: 18,
                    color: AppColors.pillGreenDark,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This race is waiting to start. Invite friends, and once '
                      '2+ have joined, tap Start Race — it won’t begin on its own.',
                      style: PixelText.body(
                        size: 13,
                        color: AppColors.textDark,
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
                        : 'Teams must be even — ${teamACount}v$teamBCount')
                  : 'Need at least 2 participants to start',
              style: PixelText.body(
                size: 12,
                color: AppColors.parchment.withValues(alpha: 0.9),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ] else if (myStatus == 'INVITED' && isTeamRace) ...[
          // TR-802: team invites are accepted by tapping a peg in the lobby
          // above — only Decline lives down here.
          PillButton(
            label: 'DECLINE INVITE',
            variant: PillButtonVariant.accent,
            fontSize: 13,
            fullWidth: true,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            onPressed: _isActing ? null : () => _respondToInvite(false),
          ),
        ] else if (myStatus == 'INVITED') ...[
          PillButton(
            label: _isActing ? 'JOINING...' : 'ACCEPT',
            variant: PillButtonVariant.primary,
            fontSize: 14,
            fullWidth: true,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            onPressed: _isActing ? null : () => _respondToInvite(true),
          ),
          const SizedBox(height: 10),
          PillButton(
            label: 'DECLINE',
            variant: PillButtonVariant.accent,
            fontSize: 13,
            fullWidth: true,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            onPressed: _isActing ? null : () => _respondToInvite(false),
          ),
        ] else if (myStatus == 'ACCEPTED') ...[
          Row(
            children: [
              Expanded(
                child: RetroCard(
                  padding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 16,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: Column(
                      children: [
                        Icon(
                          isSeeded
                              ? Icons.check_circle_rounded
                              : Icons.hourglass_top_rounded,
                          size: 32,
                          color: isSeeded
                              ? AppColors.pillGreenDark
                              : AppColors.textMid.withValues(alpha: 0.6),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isSeeded
                              ? "You're in! This race starts automatically — "
                                    'no action needed.'
                              : 'Waiting for the creator to start the race',
                          style: PixelText.body(
                            size: 14,
                            color: AppColors.textMid,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (isTeamRace) ...[
            // TR-205/208: members can leave a PENDING team lobby freely;
            // the creator's exits stay cancel/delete.
            const SizedBox(height: 10),
            PillButton(
              label: 'LEAVE LOBBY',
              variant: PillButtonVariant.accent,
              fontSize: 13,
              fullWidth: true,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              onPressed: _isActing ? null : _leaveTeamLobby,
            ),
          ],
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
        _sectionCard(child: _buildRaceInfoCard()),
        const SizedBox(height: 16),
        _sectionCard(
          child: Column(
            children: [
              Icon(
                Icons.directions_run_rounded,
                size: 32,
                color: AppColors.accent,
              ),
              const SizedBox(height: 8),
              Text(
                'This race is already underway!',
                style: PixelText.title(size: 16, color: AppColors.textDark),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                'Join now and your steps will count from when you accept.',
                style: PixelText.body(size: 14, color: AppColors.textMid),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PillButton(
                label: _isActing ? 'JOINING...' : 'JOIN RACE',
                variant: PillButtonVariant.primary,
                fontSize: 14,
                fullWidth: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                onPressed: _isActing ? null : () => _respondToInvite(true),
              ),
              const SizedBox(height: 10),
              PillButton(
                label: 'DECLINE',
                variant: PillButtonVariant.accent,
                fontSize: 13,
                fullWidth: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                onPressed: _isActing ? null : () => _respondToInvite(false),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildActiveContent() {
    // TR-901: target-steps races are gone — `targetSteps` may still arrive on
    // the wire from the backend (compat, TR-903) but is deliberately ignored.
    final buyInAmount = _readInt(_race!['buyInAmount'], fallback: 0);
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
      if (buyInAmount > 0) _prizeChip(),
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
    final participants = sortRaceParticipantsForDisplay(
      (progress['participants'] as List?)?.cast<Map<String, dynamic>>() ?? [],
    );
    final isTeamRace = TeamRace.isTeamRace(_race!);

    // Position runners against the expected-pace denominator (leader-capped)
    // so time-based races show sane positions from minute one — see
    // _courseDenominator.
    final leaderSteps = _leaderSteps(participants);
    final courseDenominator = _courseDenominator(leaderSteps);

    return Column(
      children: [
        // THE RACE — full-bleed race-day hero with HUD chips on the sky.
        _buildRaceHero(
          chips: chips,
          runners: [
            // Team races: only the two team leaders run the track (one capy per
            // side). Solo/ranked: every racer as before.
            for (final p
                in (isTeamRace ? _twoTeamLeaders(participants) : participants))
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
                    (p['accessories'] as List?)?.cast<Map<String, dynamic>>() ??
                    const [],
                animal: p['stealthed'] == true
                    ? null
                    : animalFromJson(p['animal']),
                // TR-804: team glow + pennant chrome on course capys.
                teamColor: isTeamRace
                    ? switch (TeamRace.participantTeam(p)) {
                        final team? => TeamRace.color(team),
                        null => null,
                      }
                    : null,
                // The two track capys represent their TEAM (its leader), so
                // label them by team name, not the leader's username.
                label: isTeamRace
                    ? switch (TeamRace.participantTeam(p)) {
                        final team? => TeamRace.teamName(_race!, team),
                        null => null,
                      }
                    : null,
              ),
          ],
        ),

        if (_progressState.isRefreshing)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: LinearProgressIndicator(
              minHeight: 2,
              color: AppColors.accent,
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
                        color: AppColors.pillGold,
                      ).copyWith(shadows: _headerTextShadows),
                    ),
                  if (finishRewardPool > 0) ...[
                    const SizedBox(height: 2),
                    Text(
                      finishRewardPlaces == 1
                          ? 'Winner takes $finishRewardPool gold'
                          : finishRewardPlaces > 1
                          ? 'Top $finishRewardPlaces split $finishRewardPool gold'
                          : 'Top finishers split $finishRewardPool gold',
                      textAlign: TextAlign.center,
                      style: PixelText.body(
                        size: 13,
                        color: AppColors.pillGold,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        const SizedBox(height: 18),

        // SCOREBOARD (team) — honest combined totals + lead on top, then the
        // two rosters as color-matched columns beneath their plaques. Totals
        // come from the backend team block (always honest, TR-658), falling
        // back to summing visible planks on older payloads. Solo races keep the
        // single STANDINGS list.
        StaggerIn(
          index: 0,
          child: Column(
            children: [
              _checkerSectionHeader(isTeamRace ? 'SCOREBOARD' : 'STANDINGS'),
              _sectionCard(
                padding: EdgeInsets.all(isTeamRace ? 14 : 8),
                child: isTeamRace
                    ? Column(
                        children: [
                          TeamH2HBanner(
                            teamAName: TeamRace.teamName(
                              _race!,
                              RaceTeam.teamA,
                            ),
                            teamBName: TeamRace.teamName(
                              _race!,
                              RaceTeam.teamB,
                            ),
                            teamATotal: _teamTotalFromProgress(
                              progress,
                              participants,
                              RaceTeam.teamA,
                            ),
                            teamBTotal: _teamTotalFromProgress(
                              progress,
                              participants,
                              RaceTeam.teamB,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _buildTeamTwoColumns(participants),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [..._buildLeaderboardRows(participants)],
                      ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // POWERUPS — slots, stash, and active effects on one card. Hidden for
        // a spectator (they hold no powerups and can take no actions here).
        if (!_isSpectator)
          StaggerIn(
            index: 1,
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
                        _buildInventoryContent(),
                        if (_buildNextPowerupHelper() case final helper?)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: helper,
                          ),
                      ] else
                        Row(
                          children: [
                            Icon(
                              Icons.block_rounded,
                              size: 18,
                              color: AppColors.textMid.withValues(alpha: 0.5),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Powerups are disabled for this race',
                                style: PixelText.body(
                                  size: 14,
                                  color: AppColors.textMid,
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

        // ACTIVITY & CHAT
        StaggerIn(index: 2, child: _buildActivityTabsSection()),

        // TR-601: mid-race forfeit — team races only, and only while you're
        // still in play. Deliberately last and low-key: it's a destructive,
        // permanent exit, not a headline action. Hidden entirely for a
        // tournament matchup — the bracket screen owns forfeit there, and the
        // race-level path is locked server-side (spec §6.5/§6.7).
        if (isTeamRace &&
            !_isSpectator &&
            _race?['tournamentId'] == null &&
            !_iHaveForfeited(participants)) ...[
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

  /// True once the signed-in user has forfeited this race (frozen, out of
  /// play). `forfeitedAt` is additive — absent on older payloads.
  bool _iHaveForfeited(List<Map<String, dynamic>> participants) {
    for (final p in participants) {
      if (p['userId'] == _myUserId) return TeamRace.hasForfeited(p);
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
    final participants = (race['participants'] as List?)
        ?.whereType<Map>()
        .toList();
    if (participants == null || participants.isEmpty) return false;
    return !participants.any((p) => p['userId'] == _myUserId);
  }

  Widget _buildSpectatorBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.woodDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.roofEdge, width: 2),
      ),
      child: Row(
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
              friends: widget.friends,
            ),
          ),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [AppColors.pillGold, AppColors.pillGoldDark],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.pillGoldShadow, width: 2),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$label — ${name.toUpperCase()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PixelText.title(size: 12, color: AppColors.textDark),
                  ),
                  Text(
                    'Tap to see the bracket',
                    style: PixelText.body(size: 11, color: AppColors.textDark),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textDark,
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
    if (event['active'] == false) return null;

    final endsAtRaw = event['endsAt'];
    final endsAt = endsAtRaw is String
        ? DateTime.tryParse(endsAtRaw)?.toLocal()
        : null;
    if (endsAt == null) return null;

    final remaining = endsAt.difference(_countdownNow);
    if (remaining.isNegative || remaining == Duration.zero) return null;

    final multiplier = _readNullableInt(event['multiplier']) ?? 2;

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
      'You earn a powerup every ${_formatSteps(powerupStepInterval)} steps this race. ${_formatSteps(stepsUntilNextPowerup)} to go.',
      style: PixelText.body(size: 13, color: AppColors.textMid),
    );
  }

  /// Slot mystery boxes the user can open right now (status MYSTERY_BOX).
  List<String> get _openableSlotBoxIds {
    final inventory =
        (_powerupData?['inventory'] as List?)?.cast<Map<String, dynamic>>() ??
        const [];
    return [
      for (final p in inventory)
        if ((p['status'] as String?) == 'MYSTERY_BOX' && p['id'] is String)
          p['id'] as String,
    ];
  }

  /// Total openable boxes (slot + queued overflow) — drives the "Open All"
  /// affordance, which only appears when there are at least two.
  int get _openableBoxCount => _openableSlotBoxIds.length + _queuedBoxCount;

  /// Trailing widget for the POWERUPS header: the "Open All" button (when ≥2
  /// boxes are openable) alongside the existing queued-count chip.
  Widget? _powerupsHeaderTrailing() {
    final chip = _queuedBoxesChip();
    final showOpenAll = _openableBoxCount >= 2;
    if (chip == null && !showOpenAll) return null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showOpenAll) ...[
          _OpenAllButton(onTap: _isActing ? null : _openAllBoxes),
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

    setState(() => _isActing = true);
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
          ),
          transitionsBuilder: (_, anim, _, child) =>
              FadeTransition(opacity: anim, child: child),
          transitionDuration: const Duration(milliseconds: 300),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isActing = false);
        _loadProgress();
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

      // Refresh after closing
      _loadProgress();
    } catch (e) {
      if (mounted) {
        setState(() => _isActing = false);
        showErrorToast(context, 'Failed to open mystery box');
      }
    }
  }

  Widget _buildActiveEffectsSection() {
    final effects =
        (_powerupData?['activeEffects'] as List?)
            ?.cast<Map<String, dynamic>>()
            .where(
              (e) =>
                  e['onSelf'] == true ||
                  e['targetUserId'] == widget.authService.userId,
            )
            .toList() ??
        [];

    if (effects.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(
            'ACTIVE EFFECTS',
            style: PixelText.title(size: 14, color: AppColors.textMid),
          ),
        ),
        ...effects.map((e) {
          final type = e['type'] as String?;
          final name = type == null ? 'Unknown' : PowerupCopy.nameFor(type);
          // Shipped chain: short description, else the FULL description, else
          // empty. 11 of 26 types have no short copy and rely on the
          // description here — omitting the line would blank their subtitle.
          final desc = PowerupCopy.effectRailSubtitleFor(type);
          final expiresAtStr = e['expiresAt'] as String?;

          String timeLabel;
          if (expiresAtStr != null) {
            final expiresAt = DateTime.parse(expiresAtStr);
            final remaining = expiresAt.difference(_countdownNow);
            if (remaining.isNegative) {
              timeLabel = 'Expiring...';
            } else if (remaining.inHours > 0) {
              timeLabel = '${remaining.inHours}h ${remaining.inMinutes % 60}m';
            } else if (remaining.inMinutes > 0) {
              timeLabel =
                  '${remaining.inMinutes}m ${remaining.inSeconds % 60}s';
            } else {
              timeLabel = '${remaining.inSeconds}s';
            }
          } else {
            timeLabel = 'Until used';
          }

          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                PowerupIcon(type: type ?? '', size: 22, spinning: true),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: PixelText.title(
                          size: 13,
                          color: AppColors.textDark,
                        ),
                      ),
                      Text(
                        desc,
                        style: PixelText.body(
                          size: 11,
                          color: AppColors.textMid,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.woodDark,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    timeLabel,
                    style: PixelText.title(
                      size: 11,
                      color: AppColors.parchment,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Divider(
            color: AppColors.parchmentBorder.withValues(alpha: 0.5),
            height: 1,
          ),
        ),
      ],
    );
  }

  /// "N queued" mystery-box chip for the POWERUPS section header. Null when
  /// nothing is queued so the header renders without a trailing widget.
  Widget? _queuedBoxesChip() {
    if (_queuedBoxCount <= 0) return null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.parchment.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 18, height: 20, child: SpinningCrate(size: 16)),
          const SizedBox(width: 4),
          Text(
            '$_queuedBoxCount queued',
            style: PixelText.body(size: 11, color: AppColors.coinDark),
          ),
        ],
      ),
    );
  }

  Widget _buildInventoryContent() {
    final inventory =
        (_powerupData?['inventory'] as List?)?.cast<Map<String, dynamic>>() ??
        [];
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

              if (isMysteryBox) {
                return ItemSlot(
                  state: ItemSlotState.mysteryBox,
                  isExtraSlot: isExtraSlot,
                  onTap: _isActing
                      ? null
                      : () => _openMysteryBox(pw['id'] as String),
                );
              }

              return ItemSlot(
                state: ItemSlotState.held,
                powerupType: pw['type'] as String? ?? '',
                rarity: pw['rarity'] as String?,
                isExtraSlot: isExtraSlot,
                onTap: _isActing ? null : () => _showPowerupActions(pw),
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
            // Imposter is disabled on this build (item #3): the server rejects
            // its use and drops it from the catalog. Hide any still-owned
            // Imposter from the stash so there's no dead "USE" button. The row
            // stays in the DB untouched and reappears if we re-enable.
            .where((e) => e.value > 0 && !_hiddenPowerupTypes.contains(e.key))
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key));
    if (entries.isEmpty) return const [];

    return [
      const SizedBox(height: 12),
      Text(
        'YOUR STASH',
        style: PixelText.title(size: 13, color: AppColors.textMid),
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
                  style: PixelText.body(size: 14, color: AppColors.textDark),
                ),
              ),
              PillButton(
                label: 'USE',
                variant: PillButtonVariant.secondary,
                fontSize: 11,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                onPressed: _isActing ? null : () => _redeemAndUsePowerup(e.key),
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
      final participants =
          (_race?['participants'] as List?)?.cast<Map<String, dynamic>>() ??
          const [];
      final mySteps = participants
          .where((p) => (p['userId'] as String?) == _myUserId)
          .map((p) => (p['totalSteps'] as num?)?.toInt() ?? 0)
          .fold<int>(0, (a, b) => a > b ? a : b);
      final text = mySteps > 0
          ? 'I\'ve logged ${_formatSteps(mySteps)} steps in "$raceName" on '
                'Bara. Think you can catch me? $url'
          : 'Race me in "$raceName" on Bara — bet you can\'t keep up! $url';
      await shareText(
        _shareButtonKey.currentContext ?? context,
        text,
        subject: 'Race me on Bara',
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
    final race = _race;
    if (race == null) return false;
    return race['myStatus'] == 'ACCEPTED' && race['status'] == 'ACTIVE';
  }

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
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.parchment,
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
              style: PixelText.title(size: 18, color: AppColors.textDark),
            ),
            const SizedBox(height: 16),
            PillButton(
              label: status == 'PENDING' ? 'INVITE FRIENDS' : 'INVITE MORE',
              variant: PillButtonVariant.secondary,
              fontSize: 13,
              fullWidth: true,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              onPressed: _isActing
                  ? null
                  : () {
                      Navigator.of(context).pop();
                      _inviteMore();
                    },
            ),
            const SizedBox(height: 10),
            if (status == 'PENDING') ...[
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
            const SizedBox(height: 10),
            PillButton(
              label: 'CANCEL RACE',
              variant: PillButtonVariant.accent,
              fontSize: 13,
              fullWidth: true,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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

  bool get _canPostMessage {
    final race = _race;
    if (race == null) return false;
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
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
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

  Widget _buildActivityTab() {
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
        onRetry: feed.loadInitial,
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
                  style: PixelText.body(size: 13, color: AppColors.accent),
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
        onRetry: chat.loadInitial,
      );
    } else if (messages.isEmpty) {
      body = _buildTabEmptyState('No messages yet. Say hi!');
    } else {
      body = ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
                    style: PixelText.body(size: 13, color: AppColors.accent),
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
            color: AppColors.textMid.withValues(alpha: 0.6),
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
        color: AppColors.parchmentDark.withValues(alpha: 0.3),
        child: Text(
          reason,
          style: PixelText.body(size: 14, color: AppColors.textMid),
          textAlign: TextAlign.center,
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: AppColors.parchmentLight,
        border: Border(
          top: BorderSide(color: AppColors.textMid.withValues(alpha: 0.2)),
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
              decoration: InputDecoration(
                hintText: 'Message…',
                hintStyle: PixelText.body(size: 16, color: AppColors.textMid),
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
            color: AppColors.accent,
            onPressed: _sendingMessage ? null : _sendMessage,
          ),
        ],
      ),
    );
  }

  Widget _buildCompletedContent() {
    final winner = _race!['winner'] as Map<String, dynamic>?;
    // TR-402/404: team races record winnerTeam (winnerUserId stays null), and
    // a completed team race with no winnerTeam is a TIE — never the plain
    // individual "No winner" state.
    final isTeamRace = TeamRace.isTeamRace(_race!);
    final winnerTeam = TeamRace.winnerTeam(_race!);
    final participants = sortRaceParticipantsForDisplay(
      (_progress?['participants'] as List?)?.cast<Map<String, dynamic>>() ??
          (_race!['participants'] as List?)?.cast<Map<String, dynamic>>() ??
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
                  const Icon(
                    Icons.emoji_events_rounded,
                    size: 16,
                    color: AppColors.pillGold,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'RACE COMPLETE',
                    style: PixelText.title(size: 13, color: Colors.white),
                  ),
                ],
              ),
            ),
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
              _checkerSectionHeader(isTeamRace ? 'WINNING TEAM' : 'WINNER'),
              _sectionCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    if (isTeamRace)
                      _buildTeamWinnerBoard(winnerTeam, participants)
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
                          color: AppColors.textDark,
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
                          color: AppColors.textMid,
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
          index: 1,
          child: Column(
            children: [
              _checkerSectionHeader('FINAL STANDINGS'),
              _sectionCard(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: isTeamRace
                      ? _buildTeamGroupedRows(participants)
                      : _buildLeaderboardRows(participants),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // ACTIVITY / CHAT — still viewable after the race ends. The composer
        // auto-disables (read-only) via _canPostMessage.
        StaggerIn(index: 2, child: _buildActivityTabsSection()),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildCancelledContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 64),
        Icon(
          Icons.cancel_outlined,
          size: 48,
          color: AppColors.parchment.withValues(alpha: 0.75),
        ),
        const SizedBox(height: 12),
        Text(
          'This race was cancelled',
          style: PixelText.title(
            size: 18,
            color: AppColors.parchment,
          ).copyWith(shadows: _headerTextShadows),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildPayoutBreakdown(
    List<PayoutTier> tiers, {
    Key? key,
    Color labelColor = AppColors.textMid,
    Color amountColor = AppColors.coinDark,
  }) {
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
            labelColor: labelColor,
            amountColor: amountColor,
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
                  style: PixelText.title(size: 10, color: labelColor),
                ),
                Icon(Icons.chevron_right, size: 12, color: labelColor),
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
      backgroundColor: AppColors.parchmentLight,
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
                  style: PixelText.title(size: 14, color: AppColors.textDark),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (final tier in tiers)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Row(
                              children: [
                                Text(
                                  payoutPlacementLabel(tier.placement),
                                  style: PixelText.title(
                                    size: 12,
                                    color: AppColors.textMid,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  '${tier.amount}',
                                  style: PixelText.number(
                                    size: 14,
                                    color: AppColors.coinDark,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
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
    Color labelColor = AppColors.textMid,
    Color amountColor = AppColors.coinDark,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: PixelText.title(size: 10, color: labelColor)),
        const SizedBox(width: 3),
        Text(
          _formatCoinAmount(amount),
          style: PixelText.title(size: 10, color: amountColor),
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
        badgeColor = AppColors.pillGreenDark;
        badgeText = 'JOINED';
      case 'DECLINED':
        badgeColor = AppColors.error;
        badgeText = 'DECLINED';
      default:
        badgeColor = AppColors.textMid;
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
                color: isMe ? AppColors.accent : AppColors.textDark,
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
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(
                  Icons.person_remove,
                  size: 18,
                  color: AppColors.error,
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
      backgroundColor: AppColors.parchment,
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
                    const Icon(
                      Icons.person_remove,
                      size: 22,
                      color: AppColors.error,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Remove ${atName(displayName)}?',
                        style: PixelText.title(
                          size: 18,
                          color: AppColors.textDark,
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
                  style: PixelText.body(size: 13, color: AppColors.textMid),
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
  static int _teamTotalFromProgress(
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
    return TeamRace.teamTotal(participants, team);
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
          const Icon(
            Icons.handshake_rounded,
            size: 44,
            color: AppColors.textMid,
          ),
          const SizedBox(height: 10),
          Text(
            'It\u2019s a tie \u2014 buy-ins refunded',
            textAlign: TextAlign.center,
            style: PixelText.title(size: 16, color: AppColors.textDark),
          ),
          const SizedBox(height: 4),
          Text(
            'Both teams finished dead even. Everyone got their coins back.',
            textAlign: TextAlign.center,
            style: PixelText.body(size: 12, color: AppColors.textMid),
          ),
        ],
      );
    }

    final members = TeamRace.membersOf(participants, winnerTeam);
    final color = TeamRace.color(winnerTeam);
    final colorLight = TeamRace.colorLight(winnerTeam);
    final colorDark = TeamRace.colorDark(winnerTeam);

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
                          color: AppColors.textDark,
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
    final color = TeamRace.color(team);
    final colorLight = TeamRace.colorLight(team);
    final colorDark = TeamRace.colorDark(team);
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
  /// hero — one capy per side. Skips a side with no members. Order: Team A, B.
  List<Map<String, dynamic>> _twoTeamLeaders(
    List<Map<String, dynamic>> participants,
  ) {
    final leaders = <Map<String, dynamic>>[];
    for (final team in RaceTeam.values) {
      Map<String, dynamic>? best;
      var bestSteps = -1;
      for (final p in participants) {
        if (TeamRace.participantTeam(p) != team) continue;
        final steps = (p['totalSteps'] as num?)?.toInt() ?? 0;
        if (steps > bestSteps) {
          bestSteps = steps;
          best = p;
        }
      }
      if (best != null) leaders.add(best);
    }
    return leaders;
  }

  /// Team standings as two color-matched columns (Team A | Team B) sitting
  /// under the scoreboard plaques. Bold compact cells; rank shields keep the
  /// participant's OVERALL race place.
  Widget _buildTeamTwoColumns(List<Map<String, dynamic>> participants) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _teamRosterColumn(participants, RaceTeam.teamA)),
        const SizedBox(width: 10),
        Expanded(child: _teamRosterColumn(participants, RaceTeam.teamB)),
      ],
    );
  }

  Widget _teamRosterColumn(
    List<Map<String, dynamic>> participants,
    RaceTeam team,
  ) {
    final cells = <Widget>[];
    for (var i = 0; i < participants.length; i++) {
      if (TeamRace.participantTeam(participants[i]) != team) continue;
      if (cells.isNotEmpty) cells.add(const SizedBox(height: 8));
      cells.add(_teamColumnCell(participants[i], i, team));
    }
    if (cells.isEmpty) {
      cells.add(
        Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          alignment: Alignment.center,
          child: Text(
            'No one yet',
            style: PixelText.body(size: 12.5, color: AppColors.textLight),
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
    int overallRank,
    RaceTeam team,
  ) {
    final name = p['displayName'] as String? ?? '???';
    final totalSteps = (p['totalSteps'] as num?)?.toInt() ?? 0;
    final userId = p['userId'] as String? ?? '';
    final isMe = userId == _myUserId;
    final isStealthed = p['stealthed'] == true;
    final isForfeited = TeamRace.hasForfeited(p);
    final colorLight = TeamRace.colorLight(team);
    final colorDark = TeamRace.colorDark(team);
    final accessories = isStealthed
        ? const <Map<String, dynamic>>[]
        : (p['accessories'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final animal = isStealthed ? null : animalFromJson(p['animal']);

    // Rank/avatar + name + steps, centered in the space left of the rail.
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Capy avatar (the racer's own capybara + cosmetics) with the
        // overall-rank shield tucked into its corner.
        SizedBox(
          width: 52,
          height: 46,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              CapybaraSpriteWithAccessories(
                accessories: accessories,
                capybaraSize: 46,
                frameIndex: 0,
                animal: animal,
              ),
              Positioned(
                top: -3,
                left: -2,
                child: Container(
                  width: 21,
                  height: 21,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colorDark,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Text(
                    '${overallRank + 1}',
                    style: PixelText.number(size: 11, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 7),
        Text(
          isMe ? '${atName(name)} (you)' : atName(name),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: PixelText.body(size: 15, color: AppColors.textDark),
        ),
        const SizedBox(height: 1),
        Text(
          _formatSteps(totalSteps),
          textAlign: TextAlign.center,
          style: PixelText.number(size: 18, color: colorDark),
        ),
      ],
    );

    final cell = Opacity(
      key: ValueKey('team-cell-$userId'),
      opacity: isForfeited ? 0.5 : 1.0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
        decoration: BoxDecoration(
          color: isMe
              ? colorLight.withValues(alpha: 0.22)
              : AppColors.parchmentLight,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: isMe ? colorDark : AppColors.parchmentBorder,
            width: isMe ? 2 : 1.5,
          ),
        ),
        // Every cell is at least [_kTeamCellContentMinHeight] tall and reserves
        // the effect rail on the right, so opposing cells stay aligned no
        // matter how many effects sit on each racer (spec §4). The min-height
        // child sizes the Stack; the rail (#6: rainstorm/leech/etc. on
        // opponents) is stretched to that same height beside it — hidden for
        // stealthed rows to match the plank.
        child: Stack(
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: _kTeamCellContentMinHeight,
              ),
              child: Padding(
                padding: const EdgeInsets.only(right: _kTeamEffectRailWidth),
                child: Center(child: content),
              ),
            ),
            Positioned(
              top: 0,
              bottom: 0,
              right: 0,
              child: _teamEffectRail(userId, visible: !isStealthed),
            ),
          ],
        ),
      ),
    );

    if (isMe || isStealthed || userId.isEmpty) return cell;
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
      child: cell,
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
      backgroundColor: AppColors.parchment,
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
                      color: AppColors.woodMid,
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
                        color: AppColors.textDark,
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
                  style: PixelText.body(size: 12, color: AppColors.textMid),
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
      frameColor: AppColors.parchmentBorder,
      child: Row(
        children: [
          const Icon(Icons.radar_rounded, color: AppColors.textMid, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: PixelText.body(size: 13, color: AppColors.textMid),
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
          ? AppColors.parchmentBorder
          : AppColors.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            atName(name),
            style: PixelText.title(size: 14, color: AppColors.textDark),
          ),
          const SizedBox(height: 6),
          if (defenses.isEmpty)
            Row(
              children: [
                const Icon(
                  Icons.lock_open_rounded,
                  size: 16,
                  color: AppColors.pillGreen,
                ),
                const SizedBox(width: 6),
                Text(
                  'No defenses up — safe to attack',
                  style: PixelText.body(size: 12, color: AppColors.textMid),
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
        color: AppColors.parchmentDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.parchmentBorder, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PowerupIcon(type: type, size: 18),
          const SizedBox(width: 6),
          Text(
            PowerupCopy.nameFor(type),
            style: PixelText.body(size: 12, color: AppColors.textDark),
          ),
          if (remaining != null) ...[
            const SizedBox(width: 6),
            Text(
              remaining,
              style: PixelText.body(size: 11, color: AppColors.textMid),
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

  /// Builds the active-effect badge widgets targeting [userId] — the shared
  /// filter+render used by both the solo leaderboard plank and the team-race
  /// cell (#6), so opponents show rainstorm/leech/etc. badges identically in
  /// both layouts. Leech badges resolve their attacker's name for the tooltip.
  List<Widget> _effectIconsFor(String userId) {
    return [
      for (final d in _effectDataFor(userId))
        _EffectIconWithTooltip(type: d.type, attackerName: d.attackerName),
    ];
  }

  /// The raw active-effect data targeting [userId] (type + resolved attacker
  /// name), shared by the solo plank's [_effectIconsFor] and the team cell's
  /// vertical effect rail. Kept separate from widget construction so the rail
  /// can measure/overflow the list before rendering.
  List<({String type, String? attackerName})> _effectDataFor(String userId) {
    final effects =
        (_powerupData?['activeEffects'] as List?)
            ?.cast<Map<String, dynamic>>()
            .where((e) => e['targetUserId'] == userId)
            .toList() ??
        const [];
    return [
      for (final e in effects)
        (
          type: e['type'] as String? ?? '',
          attackerName: _displayNameForUser(e['sourceUserId'] as String?),
        ),
    ];
  }

  /// The narrow right-hand effect rail for a team-roster cell (spec §4). Always
  /// occupies [_kTeamEffectRailWidth] so reserving it never shifts only the
  /// affected cells; stacks every active-effect icon vertically, and collapses
  /// any overflow past what fits into a trailing `+N` chip (multi-line tooltip)
  /// so the card never grows. Empty (but still width-reserving) when the racer
  /// is stealthed or has no effects.
  Widget _teamEffectRail(String userId, {required bool visible}) {
    final data = visible
        ? _effectDataFor(userId)
        : const <({String type, String? attackerName})>[];
    return SizedBox(
      width: _kTeamEffectRailWidth,
      child: data.isEmpty
          ? const SizedBox.shrink()
          : LayoutBuilder(
              builder: (context, constraints) {
                final available = constraints.maxHeight.isFinite
                    ? constraints.maxHeight
                    : _kTeamCellContentMinHeight;
                var maxSlots = (available / _kTeamEffectSlotHeight).floor();
                if (maxSlots < 1) maxSlots = 1;
                final overflowing = data.length > maxSlots;
                final iconCount = overflowing ? maxSlots - 1 : data.length;
                final shown = data.take(iconCount).toList();
                final rest = data.skip(iconCount).toList();
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final d in shown)
                      _EffectIconWithTooltip(
                        type: d.type,
                        attackerName: d.attackerName,
                        railMode: true,
                      ),
                    if (overflowing) _EffectOverflowChip(effects: rest),
                  ],
                );
              },
            ),
    );
  }

  /// Resolves a participant's display name from a userId, for effect tooltips.
  /// Returns null when the id is absent or not found (defensive — the effect
  /// still renders, just without an attacker suffix).
  String? _displayNameForUser(String? userId) {
    if (userId == null || userId.isEmpty) return null;
    final participants =
        (_progress?['participants'] as List?)?.cast<Map<String, dynamic>>() ??
        const [];
    for (final p in participants) {
      if (p['userId'] == userId) return p['displayName'] as String?;
    }
    return null;
  }

  Widget _buildLeaderboardPlank(
    Map<String, dynamic> p,
    int rank, {
    int? finishPlace,
    bool large = false,
  }) {
    final name = p['displayName'] as String? ?? '???';
    final totalSteps = (p['totalSteps'] as num?)?.toInt() ?? 0;
    final userId = p['userId'] as String? ?? '';
    final isMe = userId == _myUserId;
    final isStealthed = p['stealthed'] == true;
    final isFinished = p['finishedAt'] != null;

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
      // Issue 1: team standings rows are larger for legibility; solo/ranked
      // keep the defaults.
      avatarSize: large ? 40 : 32,
      nameSize: large ? 17 : 15,
      stepsSize: large ? 18 : 16,
      verticalPadding: large ? 11 : 8,
      effectIcons: _effectIconsFor(userId),
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
                    color: AppColors.parchmentDark.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.parchmentBorder.withValues(alpha: 0.45),
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
class _OpenAllButton extends StatelessWidget {
  const _OpenAllButton({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.pillGold,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.pillGoldDark, width: 1.5),
              boxShadow: const [
                BoxShadow(
                  color: AppColors.pillGoldShadow,
                  offset: Offset(2, 2),
                  blurRadius: 0,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.auto_awesome_rounded,
                  size: 14,
                  color: AppColors.textDark,
                ),
                const SizedBox(width: 4),
                Text(
                  'OPEN ALL',
                  style: PixelText.pill(size: 11, color: AppColors.textDark),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Team-roster effect rail geometry (spec §4). The rail is deliberately narrow
// and the 44pt hit-target guideline is relaxed to ~28-32pt for effect icons —
// a 44pt rail would starve the name/steps in a half-width column.
const double _kTeamCellContentMinHeight = 104;
const double _kTeamEffectRailWidth = 34;
const double _kTeamEffectSlotHeight = 32; // icon hit-target + vertical spacing

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
                      color: AppColors.woodDark,
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

class _EffectIconWithTooltip extends StatefulWidget {
  final String type;

  /// Optional attacker/source display name, appended to the tooltip (e.g. the
  /// Leech badge shown on the victim reads "…from @Otter42"). Null for effects
  /// with no distinct source.
  final String? attackerName;

  /// True inside the team-roster vertical rail (spec §4): vertical spacing and
  /// a relaxed ~28-32pt tap target instead of the plank's tight horizontal
  /// packing. Default false keeps the solo-plank layout unchanged.
  final bool railMode;

  const _EffectIconWithTooltip({
    required this.type,
    this.attackerName,
    this.railMode = false,
  });

  @override
  State<_EffectIconWithTooltip> createState() => _EffectIconWithTooltipState();
}

class _EffectIconWithTooltipState extends State<_EffectIconWithTooltip> {
  OverlayEntry? _entry;

  void _show() {
    _dismiss();
    final name = PowerupCopy.nameFor(widget.type);
    var desc = PowerupCopy.descriptionFor(widget.type);
    if (desc.isEmpty) return;
    final attacker = widget.attackerName;
    if (attacker != null && attacker.isNotEmpty) {
      desc = '$desc — from ${atName(attacker)}';
    }

    _entry = _buildClampedEffectTooltip(
      anchorContext: context,
      onDismiss: _dismiss,
      child: Text(
        '$name: $desc',
        style: PixelText.body(size: 11, color: AppColors.parchment),
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
    final name = PowerupCopy.nameFor(widget.type);
    final icon = Container(
      decoration: BoxDecoration(
        color: AppColors.woodDark,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.woodShadow, width: 0.5),
      ),
      padding: const EdgeInsets.all(1.5),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: AppColors.parchment,
          borderRadius: BorderRadius.circular(4.5),
        ),
        child: PowerupIcon(type: widget.type, size: 18),
      ),
    );

    return Semantics(
      label: name,
      button: true,
      child: Padding(
        padding: widget.railMode
            ? const EdgeInsets.symmetric(vertical: 2)
            : const EdgeInsets.only(right: 3),
        child: GestureDetector(
          behavior: widget.railMode
              ? HitTestBehavior.opaque
              : HitTestBehavior.deferToChild,
          onTap: _show,
          child: widget.railMode
              ? ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 30,
                    minHeight: 28,
                  ),
                  child: Center(child: icon),
                )
              : icon,
        ),
      ),
    );
  }
}

/// The `+N` overflow chip closing a team-roster effect rail when more effects
/// are active than fit (spec §4). Tapping it shows a multi-line tooltip listing
/// the remaining effects (with attacker suffixes), clamped on-screen like the
/// per-icon bubble.
class _EffectOverflowChip extends StatefulWidget {
  final List<({String type, String? attackerName})> effects;

  const _EffectOverflowChip({required this.effects});

  @override
  State<_EffectOverflowChip> createState() => _EffectOverflowChipState();
}

class _EffectOverflowChipState extends State<_EffectOverflowChip> {
  OverlayEntry? _entry;

  void _show() {
    _dismiss();
    final lines = <Widget>[];
    for (final e in widget.effects) {
      final name = PowerupCopy.nameFor(e.type);
      final attacker = e.attackerName;
      final text = (attacker != null && attacker.isNotEmpty)
          ? '$name — from ${atName(attacker)}'
          : name;
      if (lines.isNotEmpty) lines.add(const SizedBox(height: 3));
      lines.add(
        Text(text, style: PixelText.body(size: 11, color: AppColors.parchment)),
      );
    }

    _entry = _buildClampedEffectTooltip(
      anchorContext: context,
      onDismiss: _dismiss,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: lines,
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
    return Semantics(
      label: '${widget.effects.length} more effects',
      button: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _show,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 30, minHeight: 28),
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.woodDark,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.woodShadow, width: 0.5),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                '+${widget.effects.length}',
                style: PixelText.number(size: 12, color: AppColors.parchment),
              ),
            ),
          ),
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
    final bubbleColor = isMine ? AppColors.accent : Colors.white;
    final textColor = isMine ? Colors.white : AppColors.textDark;
    final metaColor = isMine
        ? Colors.white.withValues(alpha: 0.72)
        : AppColors.textMid.withValues(alpha: 0.8);

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
                    color: AppColors.textMid.withValues(alpha: 0.2),
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
                          color: AppColors.textMid,
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
                            color: AppColors.feedAttack,
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
