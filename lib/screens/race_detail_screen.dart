import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/loadable.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import '../utils/race_participant_display.dart';
import '../widgets/arcade_page.dart';
import '../widgets/app_avatar.dart';
import '../widgets/error_toast.dart';
import '../widgets/goal_track.dart';
import '../widgets/home_course_track.dart';
import '../widgets/info_toast.dart';
import '../widgets/pill_button.dart';
import '../widgets/retro_card.dart';
import '../widgets/trail_sign.dart';
import '../widgets/powerup_icon.dart';
import '../widgets/spinning_coin.dart';
import '../widgets/spinning_crate.dart';
import '../widgets/game_container.dart';
import '../widgets/friend_request_sheet.dart';
import '../widgets/leaderboard_plank.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/race_finishers_banner.dart';
import '../widgets/item_slot.dart';
import '../widgets/feed_bubble.dart';
import 'case_opening_screen.dart';
import 'race_chat_screen.dart';
import 'race_invite_screen.dart';

class RaceDetailScreen extends StatefulWidget {
  final AuthService authService;
  final String raceId;
  final List<Map<String, dynamic>> friends;
  final BackendApiService backendApiService;

  RaceDetailScreen({
    super.key,
    required this.authService,
    required this.raceId,
    this.friends = const [],
    BackendApiService? backendApiService,
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
  'CAMPFIRE_REST': 'Freeze briefly, then get a stronger step multiplier',
  'TRAIL_MAGNET': 'Pull your next mystery box 1,000 steps closer',
  'POCKET_WATCH': 'Extend all active timed buffs',
  'TRAIL_MINE': 'Drop a hidden trap at your current step position',
  'PINECONE_TOSS': 'Hit the runner directly ahead or behind you',
  'SNEAKY_SWAP': 'View and swap a powerup with a rival',
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
  'CAMPFIRE_REST': 'Resting, then boosted',
  'POCKET_WATCH': 'Buffs extended',
  'TRAIL_MINE': 'Mine planted',
};

const _targetedPowerups = [
  'LEG_CRAMP',
  'SHORTCUT',
  'WRONG_TURN',
  'DETOUR_SIGN',
  'SNEAKY_SWAP',
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
  Loadable<Map<String, dynamic>> _progressState = const Loadable.initial();
  Loadable<List<Map<String, dynamic>>> _feedState = const Loadable.initial();
  List<Map<String, dynamic>> _feedEvents = [];
  int _queuedBoxCount = 0;
  bool _isLoading = true;
  bool _isActing = false;
  Timer? _pollTimer;
  Timer? _countdownTimer;
  late DateTime _countdownNow;

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
    super.dispose();
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
      });

      if (details['status'] == 'ACTIVE') {
        _loadProgress();
        _startPolling();
        _startCountdown();
        if (details['powerupsEnabled'] == true) {
          _loadFeed();
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
        _progressState = Loadable.success(progress);
      });

      if (_powerupData?['enabled'] == true) {
        _loadFeed();

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
    String? swapOfferedPowerupId;
    String? swapRequestedPowerupId;

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
      if (targets.isEmpty) {
        if (mounted) showErrorToast(context, 'No targets available');
        return;
      }
      targetUserId = await _showTargetPicker(targets, type);
      if (targetUserId == null) return;

      final options = await _api.fetchSneakySwapOptions(
        identityToken: token,
        raceId: widget.raceId,
        targetUserId: targetUserId,
      );
      final ownPowerups =
          (options['ownPowerups'] as List?)?.cast<Map<String, dynamic>>() ??
          const [];
      final targetPowerups =
          (options['targetPowerups'] as List?)?.cast<Map<String, dynamic>>() ??
          const [];
      if (ownPowerups.isEmpty || targetPowerups.isEmpty) {
        if (mounted) showErrorToast(context, 'No swappable powerups available');
        return;
      }

      swapOfferedPowerupId = await _showPowerupPicker(
        title: 'SWAP AWAY',
        powerups: ownPowerups,
      );
      if (swapOfferedPowerupId == null) return;
      swapRequestedPowerupId = await _showPowerupPicker(
        title: 'TAKE FROM TARGET',
        powerups: targetPowerups,
      );
      if (swapRequestedPowerupId == null) return;
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
    try {
      final result = await _api.usePowerup(
        identityToken: token,
        raceId: widget.raceId,
        powerupId: powerup['id'] as String,
        targetUserId: targetUserId,
        targetDirection: targetDirection,
        swapOfferedPowerupId: swapOfferedPowerupId,
        swapRequestedPowerupId: swapRequestedPowerupId,
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

      if (res?['blocked'] == true) {
        showInfoToast(context, 'Blocked by Compression Socks!');
      } else {
        final tierTag = upgradeLevel > 0 ? ' (Lvl $upgradeLevel)' : '';
        showInfoToast(context, '${_powerupNames[type]}$tierTag activated!');
      }

      _loadProgress();
    } catch (e) {
      if (mounted) showErrorToast(context, e.toString());
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
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
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
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
                    onTap: () => Navigator.of(ctx).pop(t['userId'] as String?),
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
                              t['displayName'] as String? ?? '???',
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

  Future<String?> _showPowerupPicker({
    required String title,
    required List<Map<String, dynamic>> powerups,
  }) async {
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
                  title,
                  style: PixelText.title(size: 16, color: AppColors.textMid),
                ),
                const SizedBox(height: 12),
                for (final powerup in powerups)
                  GestureDetector(
                    onTap: () =>
                        Navigator.of(ctx).pop(powerup['id'] as String?),
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
                          PowerupIcon(
                            type: powerup['type'] as String? ?? '',
                            size: 28,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _powerupNames[powerup['type']] ??
                                  powerup['type'] as String? ??
                                  'Powerup',
                              style: PixelText.body(
                                size: 14,
                                color: AppColors.textDark,
                              ),
                            ),
                          ),
                          Text(
                            powerup['rarity'] as String? ?? '',
                            style: PixelText.title(
                              size: 10,
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
                if (upgradeable) ...[
                  const SizedBox(height: 12),
                  Text(
                    'YOUR COINS: $myCoins',
                    style: PixelText.title(size: 10, color: AppColors.textMid),
                  ),
                ],
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

  Future<void> _loadFeed() async {
    final previous = _feedEvents;
    if (mounted) {
      setState(() {
        _feedState = previous.isEmpty
            ? const Loadable.loading()
            : Loadable.refreshing(previous);
      });
    }

    try {
      final token = widget.authService.authToken;
      if (token == null || token.isEmpty) {
        if (mounted) {
          setState(() {
            _feedState = Loadable.error(
              'Not signed in.',
              data: previous.isEmpty ? null : previous,
            );
          });
        }
        return;
      }

      final result = await _api.fetchRaceFeed(
        identityToken: token,
        raceId: widget.raceId,
      );

      if (!mounted) return;
      final events =
          (result['events'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      setState(() {
        _feedEvents = events;
        _feedState = Loadable.success(events);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _feedState = Loadable.error(
          e.toString(),
          data: previous.isEmpty ? null : previous,
        );
      });
    }
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
                        _race?['name'] as String? ?? 'Race',
                        style: PixelText.title(
                          size: 22,
                          color: AppColors.textDark,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_race != null)
                      GestureDetector(
                        onTap: _openChat,
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(
                            Icons.chat_bubble_outline,
                            color: AppColors.textDark,
                            size: 22,
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
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: content,
      );
    }
    return content;
  }

  Widget _buildRaceInfoCard() {
    final targetSteps = _readInt(_race!['targetSteps'], fallback: 0);
    final maxDays = _readInt(_race!['maxDurationDays'], fallback: 7);
    final buyInAmount = _readInt(_race!['buyInAmount'], fallback: 0);
    final potCoins = _readInt(_race!['projectedPotCoins'], fallback: 0);
    final payouts = _race!['payouts'] as Map<String, dynamic>?;

    return RetroCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'TARGET',
                      style: PixelText.title(
                        size: 11,
                        color: AppColors.textMid,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatSteps(targetSteps),
                      style: PixelText.number(
                        size: 22,
                        color: AppColors.accent,
                      ),
                    ),
                    Text(
                      'steps',
                      style: PixelText.body(size: 11, color: AppColors.textMid),
                    ),
                  ],
                ),
              ),
              Container(width: 1, height: 40, color: AppColors.parchmentBorder),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'DURATION',
                      style: PixelText.title(
                        size: 11,
                        color: AppColors.textMid,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$maxDays',
                      style: PixelText.number(
                        size: 22,
                        color: AppColors.textDark,
                      ),
                    ),
                    Text(
                      'days',
                      style: PixelText.body(size: 11, color: AppColors.textMid),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (buyInAmount > 0) ...[
            const SizedBox(height: 12),
            Container(height: 1, color: AppColors.parchmentBorder),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        'BUY-IN',
                        style: PixelText.title(
                          size: 11,
                          color: AppColors.textMid,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$buyInAmount',
                        style: PixelText.number(
                          size: 20,
                          color: AppColors.coinDark,
                        ),
                      ),
                      Text(
                        'gold each',
                        style: PixelText.body(
                          size: 11,
                          color: AppColors.textMid,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: AppColors.parchmentBorder,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        'POT',
                        style: PixelText.title(
                          size: 11,
                          color: AppColors.textMid,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$potCoins',
                        style: PixelText.number(
                          size: 20,
                          color: AppColors.coinDark,
                        ),
                      ),
                      Text(
                        'gold',
                        style: PixelText.body(
                          size: 11,
                          color: AppColors.textMid,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (payouts != null) ...[
              const SizedBox(height: 10),
              Text(
                '1ST ${_formatCoinAmount(payouts['first'])}  •  2ND ${_formatCoinAmount(payouts['second'])}  •  3RD ${_formatCoinAmount(payouts['third'])}',
                style: PixelText.title(size: 11, color: AppColors.textMid),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildPendingContent() {
    final isCreator = _race!['isCreator'] as bool? ?? false;
    final myStatus = _race!['myStatus'] as String? ?? '';
    final participants =
        (_race!['participants'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final acceptedCount = participants
        .where((p) => p['status'] == 'ACCEPTED')
        .length;

    return Column(
      children: [
        _buildRaceInfoCard(),
        const SizedBox(height: 12),

        // Participant list
        RetroCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PARTICIPANTS ($acceptedCount)',
                style: PixelText.title(size: 16, color: AppColors.textMid),
              ),
              const SizedBox(height: 10),
              for (final p in participants) _buildParticipantRow(p),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Actions
        if (isCreator) ...[
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
            label: _isActing ? 'STARTING...' : 'START RACE',
            variant: PillButtonVariant.primary,
            fontSize: 14,
            fullWidth: true,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            onPressed: (_isActing || acceptedCount < 2) ? null : _startRace,
          ),
          if (acceptedCount < 2) ...[
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
                          Icons.hourglass_top_rounded,
                          size: 32,
                          color: AppColors.textMid.withValues(alpha: 0.6),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Waiting for the creator to start the race',
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
      children: [
        _buildRaceInfoCard(),
        const SizedBox(height: 12),
        RetroCard(
          padding: const EdgeInsets.all(16),
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
        const SizedBox(height: 12),
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

    return Column(
      children: [
        ...header,

        // Match the home tab's open spacing: content is inset, but the whole
        // active race surface is not wrapped in a framed card.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_progressState.isRefreshing)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: LinearProgressIndicator(
                    minHeight: 2,
                    color: AppColors.accent,
                    backgroundColor: Colors.transparent,
                  ),
                ),
              HomeCourseTrack(
                height: 268,
                goalSteps: targetSteps,
                runners: [
                  for (final p in participants)
                    GoalTrackRunner(
                      name: p['stealthed'] == true
                          ? '???'
                          : (p['displayName'] as String? ?? '???'),
                      progress: p['stealthed'] == true
                          ? _jitterProgress(
                              p['userId'] as String? ?? '',
                              targetSteps,
                            )
                          : targetSteps > 0 && p['totalSteps'] != null
                          ? ((p['totalSteps'] as num).toInt() / targetSteps)
                          : 0.0,
                      isUser: (p['userId'] as String?) == _myUserId,
                      isStealthed: p['stealthed'] == true,
                      profilePhotoUrl: p['profilePhotoUrl'] as String?,
                      accessories:
                          (p['accessories'] as List?)
                              ?.cast<Map<String, dynamic>>() ??
                          const [],
                    ),
                ],
              ),
              const SizedBox(height: 14),

              Row(
                key: const Key('race-target-header'),
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'RACE TO ',
                            style: PixelText.title(
                              size: 18,
                              color: AppColors.textMid,
                            ),
                          ),
                          Text(
                            _formatSteps(targetSteps),
                            style: PixelText.title(
                              size: 18,
                              color: AppColors.accent,
                            ),
                          ),
                          Text(
                            ' STEPS',
                            style: PixelText.title(
                              size: 18,
                              color: AppColors.textMid,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (_buildNextPowerupHelper() case final helper?) ...[
                const SizedBox(height: 6),
                helper,
              ],
              if (finishedCount > 0) ...[
                const SizedBox(height: 10),
                RaceFinishersBanner(
                  finishedCount: finishedCount,
                  targetSteps: targetSteps,
                ),
              ],
              const SizedBox(height: 10),
              ..._buildLeaderboardRows(participants),

              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Divider(
                  color: AppColors.parchmentBorder.withValues(alpha: 0.5),
                  height: 1,
                ),
              ),

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
                    Text(
                      'Powerups are disabled for this race',
                      style: PixelText.body(size: 14, color: AppColors.textMid),
                    ),
                  ],
                ),

              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Divider(
                  color: AppColors.parchmentBorder.withValues(alpha: 0.5),
                  height: 1,
                ),
              ),

              _buildActiveEffectsSection(),
              _buildFeedSection(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ],
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
            openMysteryBox: () => _api.openMysteryBox(
              identityToken: token,
              raceId: widget.raceId,
              powerupId: boxId,
            ),
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
          padding: const EdgeInsets.only(bottom: 8),
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
      ],
    );
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

  void _openChat() {
    final race = _race;
    if (race == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RaceChatScreen(
          authService: widget.authService,
          raceId: widget.raceId,
          raceName: race['name'] as String? ?? 'Race',
          raceStatus: race['status'] as String? ?? '',
          myStatus: race['myStatus'] as String? ?? '',
          myUserId: _myUserId,
          initialMuted: race['myChatMuted'] as bool? ?? false,
          backendApiService: widget.backendApiService,
        ),
      ),
    );
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

  Widget _buildFeedSection() {
    // Build actor name lookup from participants
    final participants =
        (_progress?['participants'] as List?)?.cast<Map<String, dynamic>>() ??
        [];
    final actorNames = <String, String>{};
    for (final p in participants) {
      final uid = p['userId'] as String? ?? '';
      final name = p['displayName'] as String? ?? '???';
      if (uid.isNotEmpty) actorNames[uid] = name;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'ACTIVITY',
              style: PixelText.title(size: 18, color: AppColors.textMid),
            ),
            GestureDetector(
              onTap: _loadFeed,
              child: Icon(
                Icons.refresh,
                size: 16,
                color: AppColors.textMid.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_feedState.shouldShowInitialLoading)
          const LoadingSkeleton(
            child: Column(
              children: [
                SkeletonLine(width: double.infinity, height: 14),
                SizedBox(height: 8),
                SkeletonLine(width: 220, height: 14),
              ],
            ),
          )
        else if (_feedState.isError && !_feedState.hasData)
          LoadErrorPanel(
            title: 'Couldn’t load activity',
            message: 'Check your connection and try again.',
            onRetry: _loadFeed,
          )
        else if (_feedEvents.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No powerup activity yet',
              style: PixelText.body(
                size: 16,
                color: AppColors.textMid.withValues(alpha: 0.6),
              ),
            ),
          )
        else ...[
          if (_feedState.isRefreshing)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: LinearProgressIndicator(
                minHeight: 2,
                color: AppColors.accent,
                backgroundColor: Colors.transparent,
              ),
            ),
          for (int i = 0; i < _feedEvents.length && i < 10; i++)
            FeedBubble(
              eventType: _feedEvents[i]['eventType'] as String? ?? '',
              powerupType: _feedEvents[i]['powerupType'] as String?,
              description: _feedEvents[i]['description'] as String? ?? '',
              actorName:
                  actorNames[_feedEvents[i]['actorUserId'] as String? ?? ''] ??
                  '???',
              relativeTime: _relativeTime(
                _feedEvents[i]['createdAt'] as String?,
              ),
              actorIsUser:
                  (_feedEvents[i]['actorUserId'] as String?) == _myUserId,
            ),
        ],
      ],
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

    return Column(
      children: [
        // Winner banner
        RetroCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Text(
                'RACE COMPLETE',
                style: PixelText.title(size: 16, color: AppColors.textMid),
              ),
              const SizedBox(height: 8),
              if (winner != null) ...[
                Icon(Icons.emoji_events, size: 40, color: AppColors.coinMid),
                const SizedBox(height: 4),
                Text(
                  winner['displayName'] as String? ?? 'Unknown',
                  style: PixelText.title(
                    size: 22,
                    color: AppColors.pillGreenDark,
                  ),
                ),
                Text(
                  'WINNER',
                  style: PixelText.title(size: 16, color: AppColors.textMid),
                ),
              ] else
                Text(
                  'No winner',
                  style: PixelText.title(size: 18, color: AppColors.textMid),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Final standings - track
        RetroCard(
          padding: const EdgeInsets.all(10),
          child: HomeCourseTrack(
            height: 268,
            goalSteps: targetSteps,
            runners: [
              for (final p in participants)
                GoalTrackRunner(
                  name: p['displayName'] as String? ?? '???',
                  progress: targetSteps > 0
                      ? (((p['totalSteps'] as num?)?.toInt() ?? 0) /
                            targetSteps)
                      : 0.0,
                  isUser: (p['userId'] as String?) == _myUserId,
                  profilePhotoUrl: p['profilePhotoUrl'] as String?,
                  accessories:
                      (p['accessories'] as List?)
                          ?.cast<Map<String, dynamic>>() ??
                      const [],
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Final standings - details
        GameContainer(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'FINAL STANDINGS',
                style: PixelText.title(size: 16, color: AppColors.textMid),
              ),
              const SizedBox(height: 10),
              ..._buildLeaderboardRows(participants),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildCancelledContent() {
    return Column(
      children: [
        const SizedBox(height: 48),
        Icon(
          Icons.cancel_outlined,
          size: 48,
          color: AppColors.textMid.withValues(alpha: 0.6),
        ),
        const SizedBox(height: 12),
        Text(
          'This race was cancelled',
          style: PixelText.title(size: 18, color: AppColors.textMid),
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
    final payouts = _race!['payouts'] as Map<String, dynamic>?;

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
        if (payouts != null) ...[
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: _buildPayoutInlineSummary(
              payouts,
              key: const Key('race-prize-pool-summary'),
              labelColor: AppColors.parchment,
              amountColor: AppColors.pillGold,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPayoutInlineSummary(
    Map<String, dynamic> payouts, {
    Key? key,
    Color labelColor = AppColors.textMid,
    Color amountColor = AppColors.coinDark,
  }) {
    return Row(
      key: key,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildPayoutInlineValue(
          label: '1ST',
          amount: payouts['first'],
          labelColor: labelColor,
          amountColor: amountColor,
        ),
        const SizedBox(width: 8),
        _buildPayoutInlineValue(
          label: '2ND',
          amount: payouts['second'],
          labelColor: labelColor,
          amountColor: amountColor,
        ),
        const SizedBox(width: 8),
        _buildPayoutInlineValue(
          label: '3RD',
          amount: payouts['third'],
          labelColor: labelColor,
          amountColor: amountColor,
        ),
      ],
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
          Expanded(
            child: Text(
              isMe ? '$name (you)' : name,
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove $displayName?'),
        content: const Text(
          'They will be removed from the race. Any held buy-in will be refunded.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
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
