import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import '../utils/race_participant_display.dart';
import '../widgets/error_toast.dart';
import '../widgets/goal_track.dart';
import '../widgets/info_toast.dart';
import '../widgets/pill_button.dart';
import '../widgets/retro_card.dart';
import '../widgets/trail_sign.dart';
import '../widgets/powerup_icon.dart';
import '../widgets/spinning_crate.dart';
import '../widgets/game_container.dart';
import '../widgets/leaderboard_plank.dart';
import '../widgets/race_finishers_banner.dart';
import '../widgets/item_slot.dart';
import '../widgets/feed_bubble.dart';
import 'case_opening_screen.dart';
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
};

const _targetedPowerups = [
  'LEG_CRAMP',
  'SHORTCUT',
  'WRONG_TURN',
  'DETOUR_SIGN',
];

const _rarityColors = {
  'COMMON': Color(0xFF8B8B8B),
  'UNCOMMON': Color(0xFF4A90D9),
  'RARE': Color(0xFFD4A017),
};

class _RaceDetailScreenState extends State<RaceDetailScreen> {
  Map<String, dynamic>? _race;
  Map<String, dynamic>? _progress;
  Map<String, dynamic>? _powerupData;
  List<Map<String, dynamic>> _feedEvents = [];
  int _queuedBoxCount = 0;
  bool _isLoading = true;
  bool _isActing = false;
  Timer? _pollTimer;
  Timer? _countdownTimer;
  late DateTime _countdownNow;

  String get _myUserId => widget.authService.userId ?? '';
  BackendApiService get _api => widget.backendApiService;

  static const _textShadows = [
    Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

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
      if (token == null || token.isEmpty) return;

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
    try {
      final token = widget.authService.authToken;
      if (token == null || token.isEmpty) return;

      final progress = await _api.fetchRaceProgress(
        identityToken: token,
        raceId: widget.raceId,
      );

      if (!mounted) return;
      setState(() {
        _progress = progress;
        _powerupData = progress['powerupData'] as Map<String, dynamic>?;
      });

      if (_powerupData?['enabled'] == true) {
        _loadFeed();

        _queuedBoxCount = (_powerupData?['queuedBoxCount'] as int?) ?? 0;
        final newBoxes = (_powerupData?['newMysteryBoxes'] as List?) ?? [];
        final newQueued = (_powerupData?['newQueuedBoxes'] as int?) ?? 0;
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
    } catch (_) {}
  }

  Future<void> _refreshWallet() async {
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) return;

    final user = await _api.fetchMe(identityToken: token);
    await widget.authService.updateCoins(
      user['coins'] as int? ?? widget.authService.coins,
    );
    await widget.authService.updateHeldCoins(
      user['heldCoins'] as int? ?? widget.authService.heldCoins,
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
    final buyInAmount = _race?['buyInAmount'] as int? ?? 0;
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

  Future<void> _usePowerup(Map<String, dynamic> powerup) async {
    final type = powerup['type'] as String;

    // For targeted powerups, show target picker
    String? targetUserId;
    if (_targetedPowerups.contains(type)) {
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
      final token = widget.authService.authToken;
      if (token == null || token.isEmpty) return;

      final result = await _api.usePowerup(
        identityToken: token,
        raceId: widget.raceId,
        powerupId: powerup['id'] as String,
        targetUserId: targetUserId,
      );

      if (!mounted) return;

      final res = result['result'] as Map<String, dynamic>?;
      if (res?['blocked'] == true) {
        showInfoToast(context, 'Blocked by Compression Socks!');
      } else {
        showInfoToast(context, '${_powerupNames[type]} activated!');
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
                              '${_formatSteps(t['totalSteps'] as int)} steps',
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

  void _showPowerupActions(Map<String, dynamic> powerup) {
    final type = powerup['type'] as String;
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
                    color:
                        _rarityColors[powerup['rarity']] ?? AppColors.textMid,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    (powerup['rarity'] as String?) ?? '',
                    style: PixelText.title(size: 9, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _powerupDescriptions[type] ?? '',
                  style: PixelText.body(size: 13, color: AppColors.textMid),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
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

  Future<void> _loadFeed() async {
    try {
      final token = widget.authService.authToken;
      if (token == null || token.isEmpty) return;

      final result = await _api.fetchRaceFeed(
        identityToken: token,
        raceId: widget.raceId,
      );

      if (!mounted) return;
      setState(() {
        _feedEvents =
            (result['events'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF87CEEB), Color(0xFFB0E0F0), Color(0xFFD4F1F9)],
          ),
        ),
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
                decoration: BoxDecoration(
                  color: const Color(0xFF87CEEB),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF87CEEB).withValues(alpha: 0.8),
                      offset: const Offset(0, 2),
                      blurRadius: 4,
                    ),
                  ],
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
                        ).copyWith(shadows: _textShadows),
                        overflow: TextOverflow.ellipsis,
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
                          clipBehavior: Clip.none,
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
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

    switch (status) {
      case 'PENDING':
        return _buildPendingContent();
      case 'ACTIVE':
        final myStatus = _race!['myStatus'] as String? ?? '';
        if (myStatus == 'INVITED') {
          return _buildInvitedToActiveContent();
        }
        return _buildActiveContent();
      case 'COMPLETED':
        return _buildCompletedContent();
      case 'CANCELLED':
        return _buildCancelledContent();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildRaceInfoCard() {
    final targetSteps = _race!['targetSteps'] as int? ?? 0;
    final maxDays = _race!['maxDurationDays'] as int? ?? 7;
    final buyInAmount = _race!['buyInAmount'] as int? ?? 0;
    final potCoins = _race!['projectedPotCoins'] as int? ?? 0;
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
                      style: PixelText.title(size: 11, color: AppColors.textMid),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatSteps(targetSteps),
                      style: PixelText.number(size: 22, color: AppColors.accent),
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
                      style: PixelText.title(size: 11, color: AppColors.textMid),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$maxDays',
                      style: PixelText.number(size: 22, color: AppColors.textDark),
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
                Container(width: 1, height: 40, color: AppColors.parchmentBorder),
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
                '1ST ${payouts['first']}  •  2ND ${payouts['second']}  •  3RD ${payouts['third']}',
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
          SizedBox(
            width: double.infinity,
            child: RetroCard(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
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
                    style: PixelText.body(size: 14, color: AppColors.textMid),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
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
    final participants = sortRaceParticipantsForDisplay(
      (_progress?['participants'] as List?)?.cast<Map<String, dynamic>>() ?? [],
    );
    final finishedCount = participants
        .where((p) => p['finishedAt'] != null)
        .length;
    final targetSteps = _race!['targetSteps'] as int? ?? 0;
    final endsAtRaw = _race!['endsAt'] as String?;
    final endsAt = endsAtRaw != null
        ? DateTime.tryParse(endsAtRaw)?.toLocal()
        : null;
    return Column(
      children: [
        // Countdown
        if (endsAt != null) _buildCountdown(endsAt),
        const SizedBox(height: 12),

        // Single card for everything
        GameContainer(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Race track
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: GoalTrack(
                  height: 300,
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
                            ? ((p['totalSteps'] as int) / targetSteps)
                            : 0.0,
                        isUser: (p['userId'] as String?) == _myUserId,
                        isStealthed: p['stealthed'] == true,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Leaderboard header
              Row(
                children: [
                  Text(
                    'RACE TO ',
                    style: PixelText.title(size: 18, color: AppColors.textMid),
                  ),
                  Text(
                    _formatSteps(targetSteps),
                    style: PixelText.title(size: 18, color: AppColors.accent),
                  ),
                  Text(
                    ' STEPS',
                    style: PixelText.title(size: 18, color: AppColors.textMid),
                  ),
                ],
              ),
              if (finishedCount > 0) ...[
                const SizedBox(height: 10),
                RaceFinishersBanner(
                  finishedCount: finishedCount,
                  targetSteps: targetSteps,
                ),
              ],
              const SizedBox(height: 10),
              ..._buildLeaderboardRows(participants),

              // Divider
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Divider(
                  color: AppColors.parchmentBorder.withValues(alpha: 0.5),
                  height: 1,
                ),
              ),

              // Powerups
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

              // Divider
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Divider(
                  color: AppColors.parchmentBorder.withValues(alpha: 0.5),
                  height: 1,
                ),
              ),

              // Active effects on current user
              _buildActiveEffectsSection(),

              // Activity feed
              _buildFeedSection(),
            ],
          ),
        ),

        const SizedBox(height: 24),
      ],
    );
  }

  Future<void> _openMysteryBox(String boxId) async {
    if (_isActing) return;

    setState(() => _isActing = true);
    try {
      final token = widget.authService.authToken;
      if (token == null) return;

      final result = await _api.openMysteryBox(
        identityToken: token,
        raceId: widget.raceId,
        powerupId: boxId,
      );

      if (!mounted) return;
      setState(() => _isActing = false);

      final openResult = result['result'] as Map<String, dynamic>? ?? result;
      final type = openResult['type'] as String? ?? '';
      final rarity = openResult['rarity'] as String? ?? 'COMMON';
      final autoActivated = openResult['autoActivated'] == true;

      await Navigator.of(context).push(
        PageRouteBuilder(
          opaque: false,
          pageBuilder: (_, _, _) => CaseOpeningScreen(
            resultType: type,
            resultRarity: rarity,
            autoActivated: autoActivated,
          ),
          transitionsBuilder: (_, anim, _, child) =>
              FadeTransition(opacity: anim, child: child),
          transitionDuration: const Duration(milliseconds: 300),
        ),
      );

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
          final desc = _powerupDescriptions[type] ?? '';
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
    final slotCount = (_powerupData?['powerupSlots'] as int?) ?? 3;

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
        if (_feedEvents.isEmpty)
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
        else
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
    );
  }

  Widget _buildCompletedContent() {
    final winner = _race!['winner'] as Map<String, dynamic>?;
    final participants = sortRaceParticipantsForDisplay(
      (_progress?['participants'] as List?)?.cast<Map<String, dynamic>>() ??
          (_race!['participants'] as List?)?.cast<Map<String, dynamic>>() ??
          [],
    );
    final targetSteps = _race!['targetSteps'] as int? ?? 0;

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
          padding: const EdgeInsets.all(6),
          child: GoalTrack(
            height: 300,
            runners: [
              for (final p in participants)
                GoalTrackRunner(
                  name: p['displayName'] as String? ?? '???',
                  progress: targetSteps > 0
                      ? ((p['totalSteps'] as int? ?? 0) / targetSteps)
                      : 0.0,
                  isUser: (p['userId'] as String?) == _myUserId,
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

  Widget _buildCountdown(DateTime endsAt) {
    final remaining = endsAt.difference(_countdownNow);
    final safe = remaining.isNegative ? Duration.zero : remaining;
    final days = safe.inDays;
    final hours = safe.inHours.remainder(24);
    final minutes = safe.inMinutes.remainder(60);
    final seconds = safe.inSeconds.remainder(60);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: GameContainer(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _CountdownUnit(value: days, label: 'DAYS'),
            const SizedBox(width: 10),
            _CountdownUnit(value: hours, label: 'HRS'),
            const SizedBox(width: 10),
            _CountdownUnit(value: minutes, label: 'MIN'),
            const SizedBox(width: 10),
            _CountdownUnit(value: seconds, label: 'SEC'),
          ],
        ),
      ),
    );
  }

  Widget _buildParticipantRow(Map<String, dynamic> p) {
    final name = p['displayName'] as String? ?? '???';
    final status = p['status'] as String? ?? '';
    final userId = p['userId'] as String? ?? '';
    final isMe = userId == _myUserId;

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
        ],
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

  Widget _buildLeaderboardPlank(
    Map<String, dynamic> p,
    int rank, {
    int? finishPlace,
  }) {
    final name = p['displayName'] as String? ?? '???';
    final totalSteps = p['totalSteps'] as int? ?? 0;
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

    return LeaderboardPlank(
      rank: rank,
      name: name,
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

  const _CountdownUnit({required this.value, required this.label});

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
        Text(label, style: PixelText.title(size: 11, color: AppColors.textMid)),
      ],
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
