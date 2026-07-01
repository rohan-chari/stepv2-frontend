import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/loadable.dart';
import '../models/race_payouts.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../services/race_chat_service.dart';
import '../services/race_feed_service.dart';
import '../styles.dart';
import '../utils/at_name.dart';
import '../utils/race_display.dart';
import '../utils/race_participant_display.dart';
import '../utils/share_helper.dart';
import '../widgets/arcade_page.dart';
import '../widgets/arcade_tab_selector.dart';
import '../widgets/app_avatar.dart';
import '../widgets/error_toast.dart';
import '../widgets/global_event_banner.dart';
import '../widgets/goal_track.dart';
import '../widgets/home_course_track.dart';
import '../widgets/info_toast.dart';
import '../widgets/pill_button.dart';
import '../widgets/retro_card.dart';
import '../widgets/trail_sign.dart';
import '../widgets/powerup_icon.dart';
import '../widgets/attack_outcome_modal.dart';
import '../widgets/spinning_coin.dart';
import '../widgets/coin_balance_badge.dart';
import '../widgets/spinning_crate.dart';
import '../widgets/game_container.dart';
import '../widgets/friend_request_sheet.dart';
import '../widgets/leaderboard_plank.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/race_finishers_banner.dart';
import '../widgets/race_ui.dart';
import '../widgets/item_slot.dart';
import '../widgets/feed_bubble.dart';
import '../widgets/player_avatar.dart';
import 'case_opening_screen.dart';
import 'edit_race_screen.dart';
import 'race_invite_screen.dart';

class RaceDetailScreen extends StatefulWidget {
  final AuthService authService;
  final String raceId;
  final List<Map<String, dynamic>> friends;
  final BackendApiService backendApiService;

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
    this.tutorialPowerupsKey,
  }) : backendApiService = backendApiService ?? BackendApiService();

  @override
  State<RaceDetailScreen> createState() => _RaceDetailScreenState();
}

const _powerupNames = {
  'LEG_CRAMP': 'Leg Cramp',
  'RED_CARD': 'Red Card',
  'SHORTCUT': 'Shortcut',
  'COMPRESSION_SOCKS': 'Compression Socks',
  'PROTEIN_SHAKE': 'Protein Shake',
  'RUNNERS_HIGH': "Runner's High",
  'SECOND_WIND': 'Second Wind',
  'STEALTH_MODE': 'Stealth Mode',
  'WRONG_TURN': 'Wrong Turn',
  'FANNY_PACK': 'Fanny Pack',
  'TRAIL_MIX': 'Trail Mix',
  'DETOUR_SIGN': 'Detour Sign',
  'LUCKY_HORSESHOE': 'Lucky Horseshoe',
  'CAMPFIRE_REST': 'Campfire Rest',
  'TRAIL_MAGNET': 'Trail Magnet',
  'POCKET_WATCH': 'Pocket Watch',
  'TRAIL_MINE': 'Trail Mine',
  'PINECONE_TOSS': 'Pinecone Toss',
  'SNEAKY_SWAP': 'Sneaky Swap',
  'MIRROR': 'Mirror',
  'CLEANSE': 'Cleanse',
  'IMPOSTER': 'Imposter',
};

const _powerupDescriptions = {
  'LEG_CRAMP': 'Freeze a rival\'s steps for 2 hours',
  'RED_CARD': 'Remove 10% of the leader\'s steps',
  'SHORTCUT': 'Steal 1,000 steps from a rival',
  'COMPRESSION_SOCKS': 'Shield against the next attack',
  'PROTEIN_SHAKE': '+1,500 bonus steps instantly',
  'RUNNERS_HIGH': '2x steps for 3 hours',
  'SECOND_WIND': 'Bonus steps based on how far behind you are',
  'STEALTH_MODE':
      'Hide your name, steps, and position on the track for 4 hours',
  'WRONG_TURN': 'Reverse a rival\'s steps for 1 hour',
  'FANNY_PACK': 'Unlock an extra powerup slot',
  'TRAIL_MIX': '+100 steps per unique powerup type used',
  'DETOUR_SIGN': 'Hide the entire leaderboard from a rival for 3 hours',
  'LUCKY_HORSESHOE': 'Guarantee a better next mystery box',
  'CAMPFIRE_REST': 'Freeze for 30 min, then multiply steps for up to 90 min',
  'TRAIL_MAGNET': 'Pull your next mystery box 1,000 steps closer',
  'POCKET_WATCH': 'Extend all active timed buffs',
  'TRAIL_MINE': 'Drop a hidden trap at your current step position',
  'PINECONE_TOSS': 'Hit the runner directly ahead or behind you',
  'SNEAKY_SWAP': 'Steal a random powerup from a rival',
  'MIRROR': 'Reflect the next attack back at the attacker',
  'CLEANSE': 'Remove all debuffs an opponent placed on you',
  'IMPOSTER': 'Swap leaderboard positions with a rival for 1 hour (cosmetic)',
};

// Short-form descriptions used in the active-effects list, where the
// countdown badge on the right already conveys the remaining duration.
const _powerupShortDescriptions = {
  'LEG_CRAMP': 'Steps frozen',
  'COMPRESSION_SOCKS': 'Shielded from next attack',
  'RUNNERS_HIGH': '2x steps',
  'STEALTH_MODE': 'Progress hidden',
  'WRONG_TURN': 'Steps reversed',
  'FANNY_PACK': 'Extra powerup slot',
  'DETOUR_SIGN': 'Leaderboard hidden',
  'LUCKY_HORSESHOE': 'Next box boosted',
  'CAMPFIRE_REST': 'Frozen, then boosted',
  'POCKET_WATCH': 'Buffs extended',
  'TRAIL_MINE': 'Mine planted',
  'MIRROR': 'Reflects next attack',
};

const _targetedPowerups = [
  'LEG_CRAMP',
  'SHORTCUT',
  'WRONG_TURN',
  'DETOUR_SIGN',
  'SNEAKY_SWAP',
  // IMPOSTER picks a rival to swap leaderboard display with — uses the same
  // target-picker flow as the other targeted powerups.
  'IMPOSTER',
];

const _rarityColors = {
  'COMMON': Color(0xFF8B8B8B),
  'UNCOMMON': Color(0xFF4A90D9),
  'RARE': Color(0xFFD4A017),
};

// Powerup upgrade tables — must match backend src/utils/powerupUpgrades.js
const _upgradeCosts = {
  'COMMON': [0, 25, 75, 225],
  'UNCOMMON': [0, 45, 135, 400],
  'RARE': [0, 50, 150, 450],
};

const _upgradeCostsByType = {
  'LUCKY_HORSESHOE': [0, 250, 600, 1200],
};

// Per-tier effect labels for the use-modal. Index 0 = base.
const _upgradeEffectLabels = {
  'PROTEIN_SHAKE': [
    '+1,500 steps',
    '+2,250 steps',
    '+3,000 steps',
    '+4,500 steps',
  ],
  'SHORTCUT': [
    'Steal up to 1,000 steps',
    'Steal up to 1,500 steps',
    'Steal up to 2,000 steps',
    'Steal up to 3,000 steps',
  ],
  'DETOUR_SIGN': [
    'Hide leaderboard 3h',
    'Hide leaderboard 4h',
    'Hide leaderboard 5h',
    'Hide leaderboard 7h',
  ],
  'TRAIL_MIX': [
    '+100 steps per unique type',
    '+150 steps per unique type',
    '+200 steps per unique type',
    '+300 steps per unique type',
  ],
  'RUNNERS_HIGH': ['2x for 3h', '2x for 4h', '2x for 5h', '2x for 7h'],
  'LEG_CRAMP': ['Freeze 2h', 'Freeze 3h', 'Freeze 4h', 'Freeze 6h'],
  'STEALTH_MODE': ['Hide 4h', 'Hide 5h', 'Hide 6.5h', 'Hide 8h'],
  'WRONG_TURN': ['Reverse 1h', 'Reverse 1.5h', 'Reverse 2h', 'Reverse 3h'],
  'COMPRESSION_SOCKS': ['Shield 24h', 'Shield 30h', 'Shield 36h', 'Shield 48h'],
  'LUCKY_HORSESHOE': [
    'Next box uncommon+',
    'Better rare odds',
    'Strong rare odds',
    'Next box rare',
  ],
  'CAMPFIRE_REST': ['2.25x boost', '2.5x boost', '2.75x boost', '3x boost'],
  'TRAIL_MAGNET': [
    'Box 1,000 steps closer',
    'Box 1,500 steps closer',
    'Box 2,000 steps closer',
    'Box 3,000 steps closer',
  ],
  'POCKET_WATCH': ['Extend 1h', 'Extend 1.5h', 'Extend 2h', 'Extend 3h'],
  'TRAIL_MINE': ['3% penalty', '5% penalty', '8% penalty', '12% penalty'],
  'PINECONE_TOSS': [
    '-750 steps',
    '-1,000 steps',
    '-1,500 steps',
    '-2,250 steps',
  ],
};

bool _isUpgradeable(String? type) => _upgradeEffectLabels.containsKey(type);

int _upgradeCostForType(String? type, String rarity, int level) {
  final typeTiers = _upgradeCostsByType[type];
  if (typeTiers != null && level >= 0 && level < typeTiers.length) {
    return typeTiers[level];
  }
  final tiers = _upgradeCosts[rarity];
  if (tiers == null || level < 0 || level >= tiers.length) return 0;
  return tiers[level];
}

class _RaceDetailScreenState extends State<RaceDetailScreen> {
  Map<String, dynamic>? _race;
  Map<String, dynamic>? _progress;
  Map<String, dynamic>? _powerupData;
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
  late DateTime _countdownNow;

  // Activity/Chat tabs state.
  // 0 = Activity (system/powerup events, default), 1 = Chat (user messages).
  int _activityTabIndex = 0;

  // Chat tab (user messages).
  RaceChatService? _chat;
  bool _chatInitialized = false;
  bool _chatHasUnread = false;
  final TextEditingController _messageInput = TextEditingController();
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
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
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
    _countdownNow = DateTime.now();
    _loadDetails();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    _messageInput.dispose();
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
        _placementMuted = (details['myPlacementAlertsMuted'] as bool? ?? false) ||
            (details['myChatMuted'] as bool? ?? false);
      });

      if (details['status'] == 'ACTIVE') {
        _loadProgress();
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

  Future<void> _loadProgress() async {
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

      final progress = await _api.fetchRaceProgress(
        identityToken: token,
        raceId: widget.raceId,
      );

      if (!mounted) return;
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
        _chat?.refreshTop();
        _feed?.refreshTop();

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
        _pollTimer?.cancel();
        _countdownTimer?.cancel();
        _loadDetails();
      }
    } catch (e) {
      if (!mounted) return;
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
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _loadProgress();
    });
  }

  void _startCountdown() {
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
  }) async {
    final type = powerup['type'] as String;
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) return;

    String? targetUserId;
    String? targetDirection;

    final participants =
        (_progress?['participants'] as List?)?.cast<Map<String, dynamic>>() ??
        [];
    final targets = participants
        .where(
          (p) =>
              (p['userId'] as String?) != _myUserId && (p['stealthed'] != true),
        )
        .toList();

    if (type == 'PINECONE_TOSS') {
      targetDirection = await _showPineconeDirectionPicker();
      if (targetDirection == null) return;
    } else if (type == 'SNEAKY_SWAP') {
      // Only offer racers who actually hold something stealable. New endpoint;
      // on an older backend (or any failure) fall back to all eligible racers.
      final swapTargets = await _resolveSneakySwapTargets(token, targets);
      if (swapTargets.isEmpty) {
        if (mounted) {
          showInfoToast(
            context,
            'No one has a powerup to steal right now',
          );
        }
        return;
      }
      // Steal redesign: pick a target and the server takes one RANDOM
      // stealable powerup from them — nothing of yours is given up, so the
      // old two-step SWAP AWAY / TAKE FROM TARGET pickers are gone.
      targetUserId = await _showTargetPicker(swapTargets, type);
      if (targetUserId == null) return;
    } else if (_targetedPowerups.contains(type)) {
      final participants =
          (_progress?['participants'] as List?)?.cast<Map<String, dynamic>>() ??
          [];
      final targets = participants
          .where(
            (p) =>
                (p['userId'] as String?) != _myUserId &&
                (p['stealthed'] != true),
          )
          .toList();

      if (targets.isEmpty) {
        if (mounted) showErrorToast(context, 'No targets available');
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
      if (outcome == AttackOutcome.blocked ||
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
              ? 'You stole a ${_powerupNames[stolenType] ?? stolenType}!'
              : '${_powerupNames[type]} activated!',
        );
      } else {
        final tierTag = upgradeLevel > 0 ? ' (Lvl $upgradeLevel)' : '';
        showInfoToast(context, '${_powerupNames[type]}$tierTag activated!');
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
        showInfoToast(context, '${_powerupNames[powerup['type']]} discarded');
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
          'displayName':
              live?['displayName'] ?? t['displayName'] ?? '???',
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
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TARGET FOR ${_powerupNames[powerupType]?.toUpperCase()}',
                    style: PixelText.title(size: 16, color: AppColors.textMid),
                  ),
                  const SizedBox(height: 12),
                  for (final t in targets)
                    GestureDetector(
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
                    ),
                ],
              ),
            ),
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

  void _showPowerupActions(Map<String, dynamic> powerup) {
    final type = powerup['type'] as String;
    final rarity = (powerup['rarity'] as String?) ?? 'COMMON';
    final upgradeable = _isUpgradeable(type);
    final tierLabels = _upgradeEffectLabels[type];
    final myCoins = widget.authService.coins;

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
                          _powerupNames[type] ?? type,
                          style: PixelText.title(
                            size: 18,
                            color: AppColors.textDark,
                          ),
                        ),
                      ],
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: CoinBalanceBadge(
                        coins: myCoins,
                        coinSize: 16,
                      ),
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
                  _powerupDescriptions[type] ?? '',
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
      final cost = _upgradeCostForType(type, rarity, level);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ArcadePageBackground(
        showHeader: false,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // Header (fixed, does not scroll)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: const BoxDecoration(
                  color: AppColors.parchmentLight,
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(true),
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(
                          Icons.arrow_back,
                          color: AppColors.textDark,
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
                          color: AppColors.textDark,
                        ),
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
                                    color: AppColors.textDark,
                                  ),
                                )
                              : const Icon(
                                  Icons.ios_share,
                                  color: AppColors.textDark,
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
                            color: AppColors.textDark,
                            size: 24,
                          ),
                        ),
                      ),
                    if (_race != null &&
                        (_race!['isCreator'] as bool? ?? false) &&
                        (_race!['status'] == 'PENDING' ||
                            _race!['status'] == 'ACTIVE'))
                      GestureDetector(
                        onTap: _showRaceOptionsSheet,
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(
                            Icons.more_horiz,
                            color: AppColors.textDark,
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
                    ? const Center(child: Text('Failed to load race'))
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    final status = _race!['status'] as String;

    Widget content;
    bool wrapWithHorizontalPadding = true;

    switch (status) {
      case 'PENDING':
        content = _buildPendingContent();
        break;
      case 'ACTIVE':
        final myStatus = _race!['myStatus'] as String? ?? '';
        if (myStatus == 'INVITED') {
          content = _buildInvitedToActiveContent();
        } else {
          // _buildActiveContent applies its own per-child horizontal padding so
          // the status board (countdown + prize pool) can render full-width.
          content = _buildActiveContent();
          wrapWithHorizontalPadding = false;
        }
        break;
      case 'COMPLETED':
        content = _buildCompletedContent();
        break;
      case 'CANCELLED':
        content = _buildCancelledContent();
        break;
      default:
        return const SizedBox.shrink();
    }

    if (wrapWithHorizontalPadding) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: content,
      );
    }
    return content;
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(
          title: 'RACE DETAILS',
          icon: Icons.info_outline_rounded,
        ),
        const SizedBox(height: 8),
        _buildRaceInfoCard(),
        const SizedBox(height: 16),

        SectionHeader(
          title: 'PARTICIPANTS',
          icon: Icons.groups_rounded,
          trailing: Pill(
            label: '$acceptedCount',
            background: AppColors.parchmentDark,
            foreground: AppColors.textMid,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final p in participants) _buildParticipantRow(p)],
        ),
        const SizedBox(height: 16),

        // 1.1.7: scheduled auto-start banner, shown to every viewer of a
        // PENDING race that has a future scheduledStartAt. Live countdown,
        // driven by the same 1s ticker the active-race countdown uses.
        if (scheduledInFuture) ...[
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
                      Text(
                        'STARTS IN ${_formatCountdownShort(scheduledStartAt.difference(_countdownNow))}',
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
                      style: PixelText.body(size: 13, color: AppColors.textDark),
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
          PillButton(
            label: scheduledInFuture
                ? 'AUTO-START SCHEDULED'
                : (_isActing ? 'STARTING...' : 'START RACE'),
            variant: PillButtonVariant.primary,
            fontSize: 14,
            fullWidth: true,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            onPressed: (scheduledInFuture || _isActing || acceptedCount < 2)
                ? null
                : _startRace,
          ),
          if (!scheduledInFuture && acceptedCount < 2) ...[
            const SizedBox(height: 6),
            Text(
              'Need at least 2 participants to start',
              style: PixelText.body(size: 12, color: AppColors.textMid),
              textAlign: TextAlign.center,
            ),
          ],
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
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildInvitedToActiveContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(
          title: 'RACE DETAILS',
          icon: Icons.info_outline_rounded,
        ),
        const SizedBox(height: 8),
        _buildRaceInfoCard(),
        const SizedBox(height: 16),
        Column(
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
        const SizedBox(height: 16),
        PillButton(
          label: _isActing ? 'JOINING...' : 'JOIN RACE',
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
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildActiveContent() {
    final targetSteps = _readInt(_race!['targetSteps'], fallback: 0);
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

    final header = <Widget>[
      if (endsAt != null || buyInAmount > 0) ...[
        _buildRaceStatusBoard(endsAt: endsAt, showPrizePool: buyInAmount > 0),
        const SizedBox(height: 12),
      ],
    ];

    if (_progressState.shouldShowInitialLoading) {
      return Column(
        children: [
          ...header,
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
          ...header,
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
    final finishedCount = participants
        .where((p) => p['finishedAt'] != null)
        .length;

    // Position runners against the expected-pace denominator (leader-capped)
    // so time-based races show sane positions from minute one — see
    // _courseDenominator.
    final leaderSteps = _leaderSteps(participants);
    final courseDenominator = _courseDenominator(leaderSteps);
    final milestoneProgress = targetSteps > 0 && courseDenominator > 0
        ? (targetSteps / courseDenominator).clamp(0.0, 1.0).toDouble()
        : null;

    return Column(
      children: [
        ...header,

        if (_progressState.isRefreshing)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: LinearProgressIndicator(
              minHeight: 2,
              color: AppColors.accent,
              backgroundColor: Colors.transparent,
            ),
          ),

        // GLOBAL STEP EVENT — "2x STEPS" banner with a countdown, shown only
        // while an event window is active. Absent for old responses.
        if (_buildGlobalEventBanner() case final banner?)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: banner,
          ),

        // THE COURSE — full-bleed race visualization.
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: SectionHeader(title: 'THE COURSE', icon: Icons.flag_rounded),
        ),
        HomeCourseTrack(
          height: 268,
          goalSteps: targetSteps,
          milestoneProgress: milestoneProgress,
          milestoneLabel: _formatStepsCompact(targetSteps),
          runners: [
            for (final p in participants)
              GoalTrackRunner(
                name: p['stealthed'] == true
                    ? '???'
                    : (p['displayName'] as String? ?? '???'),
                progress: p['stealthed'] == true
                    ? _jitterProgress(p['userId'] as String? ?? '', targetSteps)
                    : _courseProgress(p['totalSteps'], courseDenominator),
                isUser: (p['userId'] as String?) == _myUserId,
                isStealthed: p['stealthed'] == true,
                profilePhotoUrl: p['profilePhotoUrl'] as String?,
                accessories:
                    (p['accessories'] as List?)?.cast<Map<String, dynamic>>() ??
                    const [],
              ),
          ],
        ),
        if (targetSteps > 0 || finishRewardPool > 0 || endsAt == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Column(
              key: const Key('race-target-header'),
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (endsAt == null)
                  Text(
                    'RACE IN PROGRESS',
                    style: PixelText.title(size: 16, color: AppColors.accent),
                  ),
                if (targetSteps > 0)
                  Text(
                    'Goal: ${_formatStepsCompact(targetSteps)}',
                    style: PixelText.body(size: 13, color: AppColors.textMid),
                  ),
                if (finishRewardPool > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    finishRewardPlaces == 1
                        ? 'Winner takes $finishRewardPool gold'
                        : finishRewardPlaces > 1
                        ? 'Top $finishRewardPlaces split $finishRewardPool gold'
                        : 'Top finishers split $finishRewardPool gold',
                    style: PixelText.body(size: 13, color: AppColors.coinDark),
                  ),
                ],
              ],
            ),
          ),
        if (_buildNextPowerupHelper() case final helper?)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: helper,
          ),
        const SizedBox(height: 18),

        // STANDINGS — full-width rows.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SectionHeader(
            title: 'STANDINGS',
            icon: Icons.leaderboard_rounded,
            trailing: finishedCount > 0
                ? Pill(
                    label: '$finishedCount FINISHED',
                    background: AppColors.pillGreen,
                    foreground: AppColors.pillGreenDark,
                    fontSize: 11,
                  )
                : null,
          ),
        ),
        const SizedBox(height: 8),
        if (finishedCount > 0) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: RaceFinishersBanner(
              finishedCount: finishedCount,
              targetSteps: targetSteps,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _buildLeaderboardRows(participants),
          ),
        ),
        const SizedBox(height: 18),

        // POWERUPS — inventory + active effects keep their own headings.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_powerupData != null && _powerupData!['enabled'] == true)
                _buildInventoryContent()
              else
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
        const SizedBox(height: 18),

        // ACTIVITY & CHAT
        _buildActivityTabsSection(),
        const SizedBox(height: 24),
      ],
    );
  }

  // "2x STEPS — ends in mm:ss" banner for an active global step-multiplier
  // event. Returns null when there is no active event (or the response omitted
  // the field, e.g. an older backend), or once the countdown has elapsed.
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
            openMysteryBox: () async {
              final result = await _api.openMysteryBox(
                identityToken: token,
                raceId: widget.raceId,
                powerupId: boxId,
              );
              // The overlay is non-opaque, so the inventory row stays visible
              // behind the reveal. Empty the box's slot as soon as the server
              // confirms — on slow connections it used to sit there until the
              // post-close _loadProgress() returned, looking like the box had
              // bounced back into the inventory.
              _optimisticallyRemoveFromInventory(boxId);
              return result;
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
          final name = _powerupNames[type] ?? type ?? 'Unknown';
          final desc =
              _powerupShortDescriptions[type] ??
              _powerupDescriptions[type] ??
              '';
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
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'POWERUPS',
              style: PixelText.title(size: 18, color: AppColors.textMid),
            ),
            if (_queuedBoxCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.coinLight.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 20,
                      child: SpinningCrate(size: 16),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$_queuedBoxCount queued',
                      style: PixelText.body(
                        size: 11,
                        color: AppColors.coinDark,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
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
    final entries = _globalPowerupInventory.entries
        .where((e) => e.value > 0)
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
                  '${_powerupNames[e.key] ?? e.key} x${e.value}',
                  style: PixelText.body(size: 14, color: AppColors.textDark),
                ),
              ),
              PillButton(
                label: 'USE',
                variant: PillButtonVariant.secondary,
                fontSize: 11,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
      await shareText(
        _shareButtonKey.currentContext ?? context,
        'Join me in "$raceName" on Bara! $url',
        subject: 'Join my step race on Bara',
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
        ArcadeTabSelector(
          labels: const ['ACTIVITY', 'CHAT'],
          activeIndex: _activityTabIndex,
          onChanged: _onTabChanged,
          unread: [false, _chatHasUnread],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 400,
          child: _activityTabIndex == 0 ? _buildActivityTab() : _buildChatTab(),
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
      final reason = status == 'COMPLETED'
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
    final participants = sortRaceParticipantsForDisplay(
      (_progress?['participants'] as List?)?.cast<Map<String, dynamic>>() ??
          (_race!['participants'] as List?)?.cast<Map<String, dynamic>>() ??
          [],
    );
    final targetSteps = _readInt(_race!['targetSteps'], fallback: 0);
    final completedLeaderSteps = _leaderSteps(participants);
    final winnerId = winner?['id'] as String?;
    final winnerEntry = participants.firstWhere(
      (p) => (p['userId'] as String?) == winnerId,
      orElse: () => const <String, dynamic>{},
    );
    final winnerAccessories =
        (winnerEntry['accessories'] as List?)?.cast<Map<String, dynamic>>() ??
        const <Map<String, dynamic>>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Winner — the arcade celebratory hero.
        GameContainer(
          padding: const EdgeInsets.all(20),
          frameColor: AppColors.accent,
          surfaceColor: AppColors.accent,
          child: Column(
            children: [
              Text(
                'RACE COMPLETE',
                style: PixelText.title(
                  size: 13,
                  color: AppColors.parchment.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: 12),
              if (winner != null) ...[
                RacerAvatar(rank: 1, accessories: winnerAccessories, size: 64),
                const SizedBox(height: 10),
                Text(
                  winner['displayName'] is String
                      ? atName(winner['displayName'] as String)
                      : 'Unknown',
                  style: PixelText.title(size: 22, color: AppColors.parchment),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                const PlacementPill(placement: 1),
              ] else
                Text(
                  'No winner',
                  style: PixelText.title(size: 18, color: AppColors.parchment),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // THE COURSE — final positions.
        const SectionHeader(title: 'THE COURSE', icon: Icons.flag_rounded),
        const SizedBox(height: 8),
        HomeCourseTrack(
          height: 268,
          goalSteps: targetSteps,
          milestoneProgress: targetSteps > 0 && completedLeaderSteps > 0
              ? (targetSteps / completedLeaderSteps).clamp(0.0, 1.0).toDouble()
              : null,
          milestoneLabel: _formatStepsCompact(targetSteps),
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
              ),
          ],
        ),
        const SizedBox(height: 18),

        // FINAL STANDINGS
        const SectionHeader(
          title: 'FINAL STANDINGS',
          icon: Icons.leaderboard_rounded,
        ),
        const SizedBox(height: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _buildLeaderboardRows(participants),
        ),
        const SizedBox(height: 18),

        // ACTIVITY / CHAT — still viewable after the race ends. The composer
        // auto-disables (read-only) via _canPostMessage.
        _buildActivityTabsSection(),
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
          color: AppColors.textMid.withValues(alpha: 0.6),
        ),
        const SizedBox(height: 12),
        Text(
          'This race was cancelled',
          style: PixelText.title(size: 18, color: AppColors.textMid),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildRaceStatusBoard({
    required DateTime? endsAt,
    required bool showPrizePool,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: GameContainer(
        key: showPrizePool
            ? const Key('race-prize-pool-board')
            : const Key('race-status-board'),
        padding: EdgeInsets.zero,
        frameColor: AppColors.accent,
        surfaceColor: AppColors.accent,
        child: CustomPaint(
          painter: const ArcadeCheckerPainter(tile: 20),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (endsAt != null) _buildCountdownSummary(endsAt),
                  if (endsAt != null && showPrizePool)
                    Container(
                      height: 2,
                      margin: const EdgeInsets.symmetric(vertical: 14),
                      color: AppColors.parchmentLight.withValues(alpha: 0.18),
                    ),
                  if (showPrizePool) _buildPrizePoolSummary(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCountdownSummary(DateTime endsAt) {
    final remaining = endsAt.difference(_countdownNow);
    final safe = remaining.isNegative ? Duration.zero : remaining;
    final days = safe.inDays;
    final hours = safe.inHours.remainder(24);
    final minutes = safe.inMinutes.remainder(60);
    final seconds = safe.inSeconds.remainder(60);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'TIME LEFT',
          style: PixelText.title(size: 13, color: AppColors.parchmentLight),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _CountdownUnit(
                value: days,
                label: 'DAYS',
                labelColor: AppColors.parchment,
              ),
              const SizedBox(width: 10),
              _CountdownUnit(
                value: hours,
                label: 'HRS',
                labelColor: AppColors.parchment,
              ),
              const SizedBox(width: 10),
              _CountdownUnit(
                value: minutes,
                label: 'MIN',
                labelColor: AppColors.parchment,
              ),
              const SizedBox(width: 10),
              _CountdownUnit(
                value: seconds,
                label: 'SEC',
                labelColor: AppColors.parchment,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPrizePoolSummary() {
    final potCoins = _readInt(_race!['projectedPotCoins'], fallback: 0);
    final payoutTiers = parsePayoutTiers(_race);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'PRIZE POOL',
          style: PixelText.title(size: 14, color: AppColors.parchmentLight),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          '$potCoins',
          style: PixelText.number(size: 30, color: AppColors.pillGold),
          textAlign: TextAlign.center,
        ),
        Text(
          'gold',
          style: PixelText.body(size: 12, color: AppColors.parchment),
          textAlign: TextAlign.center,
        ),
        if (payoutTiers.isNotEmpty) ...[
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: _buildPayoutBreakdown(
              payoutTiers,
              key: const Key('race-prize-pool-summary'),
              labelColor: AppColors.parchment,
              amountColor: AppColors.pillGold,
            ),
          ),
        ],
      ],
    );
  }

  // Inline payout breakdown: the podium (top 3) plus a tappable "+N MORE" that
  // opens the full per-place list. For winner-takes-all / top-3 this is just the
  // podium; for the field-scaled presets (top half, everyone but last) a big
  // race can pay many places, so the rest live behind the tap rather than
  // overflowing the card.
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

  Widget _buildLeaderboardPlank(
    Map<String, dynamic> p,
    int rank, {
    int? finishPlace,
  }) {
    final name = p['displayName'] as String? ?? '???';
    final totalSteps = (p['totalSteps'] as num?)?.toInt() ?? 0;
    final userId = p['userId'] as String? ?? '';
    final isMe = userId == _myUserId;
    final isStealthed = p['stealthed'] == true;
    final isFinished = p['finishedAt'] != null;

    final activeEffects =
        (_powerupData?['activeEffects'] as List?)
            ?.cast<Map<String, dynamic>>()
            .where((e) => e['targetUserId'] == userId)
            .toList() ??
        [];

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
      effectIcons: [
        for (final e in activeEffects)
          _EffectIconWithTooltip(type: e['type'] as String? ?? ''),
      ],
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
  static double _jitterProgress(String userId, int targetSteps) {
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
    final expected =
        _baselineStepsPerDay * days * math.max(elapsedFrac, 0.15);
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

  /// Compact step label for milestone markers / subtitles (e.g. 50000 -> 50K).
  static String _formatStepsCompact(int n) {
    if (n >= 1000 && n % 1000 == 0) return '${n ~/ 1000}K';
    if (n >= 10000) return '${(n / 1000).round()}K';
    return _formatSteps(n);
  }
}

class _CountdownUnit extends StatelessWidget {
  final int value;
  final String label;
  final Color labelColor;

  const _CountdownUnit({
    required this.value,
    required this.label,
    this.labelColor = AppColors.textMid,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.woodDark,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: AppColors.woodShadow.withValues(alpha: 0.5),
                offset: const Offset(0, 3),
                blurRadius: 6,
              ),
            ],
          ),
          child: Text(
            value.toString().padLeft(2, '0'),
            style: PixelText.number(size: 26, color: AppColors.parchment),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: PixelText.title(size: 11, color: labelColor)),
      ],
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

class _EffectIconWithTooltip extends StatefulWidget {
  final String type;
  const _EffectIconWithTooltip({required this.type});

  @override
  State<_EffectIconWithTooltip> createState() => _EffectIconWithTooltipState();
}

class _EffectIconWithTooltipState extends State<_EffectIconWithTooltip> {
  OverlayEntry? _entry;

  void _show() {
    _dismiss();
    final name = _powerupNames[widget.type] ?? widget.type;
    final desc = _powerupDescriptions[widget.type] ?? '';
    if (desc.isEmpty) return;

    final box = context.findRenderObject() as RenderBox;
    final offset = box.localToGlobal(Offset.zero);

    _entry = OverlayEntry(
      builder: (ctx) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _dismiss,
        child: Stack(
          children: [
            Positioned(
              left: offset.dx - 60,
              top: offset.dy - 68,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 200),
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
                  child: Text(
                    '$name: $desc',
                    style: PixelText.body(size: 11, color: AppColors.parchment),
                  ),
                ),
              ),
            ),
          ],
        ),
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
    return Padding(
      padding: const EdgeInsets.only(right: 3),
      child: GestureDetector(
        onTap: _show,
        child: Container(
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
