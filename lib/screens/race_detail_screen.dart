import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import '../widgets/error_toast.dart';
import '../widgets/goal_track.dart';
import '../widgets/info_toast.dart';
import '../widgets/pill_button.dart';
import '../widgets/retro_card.dart';
import '../widgets/powerup_icon.dart';
import 'race_invite_screen.dart';

class RaceDetailScreen extends StatefulWidget {
  final AuthService authService;
  final String raceId;
  final List<Map<String, dynamic>> friends;

  const RaceDetailScreen({
    super.key,
    required this.authService,
    required this.raceId,
    this.friends = const [],
  });

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
};

const _powerupDescriptions = {
  'LEG_CRAMP': 'Freeze a rival\'s steps for 2 hours',
  'RED_CARD': 'Remove 10% of the leader\'s steps',
  'SHORTCUT': 'Steal 1,000 steps from a rival',
  'COMPRESSION_SOCKS': 'Shield against the next attack',
  'PROTEIN_SHAKE': '+1,500 bonus steps instantly',
  'RUNNERS_HIGH': '2x steps for 3 hours',
  'SECOND_WIND': 'Bonus steps based on how far behind you are',
  'STEALTH_MODE': 'Hide your progress for 4 hours',
  'WRONG_TURN': 'Reverse a rival\'s steps for 1 hour',
  'FANNY_PACK': 'Unlock an extra powerup slot',
};

const _targetedPowerups = ['LEG_CRAMP', 'SHORTCUT', 'WRONG_TURN'];

const _rarityColors = {
  'COMMON': Color(0xFF8B8B8B),
  'UNCOMMON': Color(0xFF4A90D9),
  'RARE': Color(0xFFD4A017),
};

class _RaceDetailScreenState extends State<RaceDetailScreen> {
  final BackendApiService _api = BackendApiService();
  Map<String, dynamic>? _race;
  Map<String, dynamic>? _progress;
  Map<String, dynamic>? _powerupData;
  List<Map<String, dynamic>> _feedEvents = [];
  bool _isLoading = true;
  bool _isActing = false;
  Timer? _pollTimer;
  Timer? _countdownTimer;
  late DateTime _countdownNow;

  String get _myUserId => widget.authService.userId ?? '';

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

        // Check for auto-activated Fanny Pack
        final newBoxes = (_powerupData?['newBoxesEarned'] as List?) ?? [];
        for (final box in newBoxes) {
          if (box is Map && box['type'] == 'FANNY_PACK' && box['autoActivated'] == true) {
            _showFannyPackActivation();
            break;
          }
        }
      }

      if (progress['status'] == 'COMPLETED') {
        _pollTimer?.cancel();
        _countdownTimer?.cancel();
        _loadDetails();
      }
    } catch (_) {}
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

  Future<void> _respondToInvite(bool accept) async {
    setState(() => _isActing = true);
    try {
      final token = widget.authService.authToken;
      if (token == null || token.isEmpty) return;

      await _api.respondToRaceInvite(
        identityToken: token,
        raceId: widget.raceId,
        accept: accept,
      );

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

  Future<void> _cancelRace() async {
    setState(() => _isActing = true);
    try {
      final token = widget.authService.authToken;
      if (token == null || token.isEmpty) return;

      await _api.cancelRace(identityToken: token, raceId: widget.raceId);
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
    final existingIds =
        participants.map((p) => p['userId'] as String).toSet();

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
      final participants = (_progress?['participants'] as List?)
              ?.cast<Map<String, dynamic>>() ??
          [];
      final targets = participants
          .where((p) =>
              (p['userId'] as String?) != _myUserId &&
              (p['stealthed'] != true))
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
      List<Map<String, dynamic>> targets, String powerupType) async {
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
                Text('TARGET FOR ${_powerupNames[powerupType]?.toUpperCase()}',
                    style:
                        PixelText.title(size: 13, color: AppColors.textMid)),
                const SizedBox(height: 12),
                for (final t in targets)
                  GestureDetector(
                    onTap: () =>
                        Navigator.of(ctx).pop(t['userId'] as String?),
                    child: Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
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
                                  size: 14, color: AppColors.textDark),
                            ),
                          ),
                          if (t['totalSteps'] != null)
                            Text(
                              '${_formatSteps(t['totalSteps'] as int)} steps',
                              style: PixelText.number(
                                  size: 12, color: AppColors.textMid),
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

  void _showFannyPackActivation() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColors.parchment,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const PowerupIcon(type: 'FANNY_PACK', size: 48),
              const SizedBox(height: 12),
              Text(
                'Fanny Pack Activated!',
                style: PixelText.title(size: 18, color: AppColors.coinDark),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Your inventory was full, so the Fanny Pack was auto-equipped. You now have an extra powerup slot!',
                style: PixelText.body(size: 13, color: AppColors.textMid),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              PillButton(
                label: 'NICE',
                variant: PillButtonVariant.primary,
                fontSize: 14,
                fullWidth: true,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ],
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
                    PowerupIcon(type: type, size: 22),
                    const SizedBox(width: 6),
                    Text(
                      _powerupNames[type] ?? type,
                      style: PixelText.title(size: 18, color: AppColors.textDark),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _rarityColors[powerup['rarity']] ??
                        AppColors.textMid,
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
                      horizontal: 24, vertical: 12),
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
                      horizontal: 24, vertical: 10),
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
        _feedEvents = (result['events'] as List?)
                ?.cast<Map<String, dynamic>>() ??
            [];
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
              // Header
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(true),
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.arrow_back,
                            color: AppColors.textDark, size: 24),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _race?['name'] as String? ?? 'Race',
                        style: PixelText.title(
                                size: 22, color: AppColors.textDark)
                            .copyWith(shadows: _textShadows),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.accent))
                    : _race == null
                        ? const Center(child: Text('Failed to load race'))
                        : RefreshIndicator(
                            onRefresh: _loadDetails,
                            color: AppColors.accent,
                            backgroundColor: AppColors.parchment,
                            child: SingleChildScrollView(
                              clipBehavior: Clip.none,
                              physics:
                                  const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16),
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

    return RetroCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text('TARGET',
                    style: PixelText.title(
                        size: 11, color: AppColors.textMid)),
                const SizedBox(height: 4),
                Text(_formatSteps(targetSteps),
                    style: PixelText.number(
                        size: 22, color: AppColors.accent)),
                Text('steps',
                    style: PixelText.body(
                        size: 11, color: AppColors.textMid)),
              ],
            ),
          ),
          Container(
              width: 1, height: 40, color: AppColors.parchmentBorder),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text('DURATION',
                    style: PixelText.title(
                        size: 11, color: AppColors.textMid)),
                const SizedBox(height: 4),
                Text('$maxDays',
                    style: PixelText.number(
                        size: 22, color: AppColors.textDark)),
                Text('days',
                    style: PixelText.body(
                        size: 11, color: AppColors.textMid)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingContent() {
    final isCreator = _race!['isCreator'] as bool? ?? false;
    final myStatus = _race!['myStatus'] as String? ?? '';
    final participants =
        (_race!['participants'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final acceptedCount =
        participants.where((p) => p['status'] == 'ACCEPTED').length;

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
              Text('PARTICIPANTS ($acceptedCount)',
                  style:
                      PixelText.title(size: 13, color: AppColors.textMid)),
              const SizedBox(height: 10),
              for (final p in participants) _buildParticipantRow(p),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Actions
        if (isCreator) ...[
          PillButton(
            label: _isActing ? 'INVITING...' : 'INVITE FRIENDS',
            variant: PillButtonVariant.secondary,
            fontSize: 13,
            fullWidth: true,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
          const SizedBox(height: 10),
          PillButton(
            label: 'CANCEL RACE',
            variant: PillButtonVariant.accent,
            fontSize: 13,
            fullWidth: true,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            onPressed: _isActing ? null : _cancelRace,
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
          SizedBox(
            width: double.infinity,
            child: RetroCard(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            child: Column(
              children: [
                Icon(Icons.hourglass_top_rounded,
                    size: 32, color: AppColors.textMid.withValues(alpha: 0.6)),
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

  Widget _buildActiveContent() {
    final participants = (_progress?['participants'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        [];
    final targetSteps = _race!['targetSteps'] as int? ?? 0;
    final endsAtRaw = _race!['endsAt'] as String?;
    final endsAt =
        endsAtRaw != null ? DateTime.tryParse(endsAtRaw)?.toLocal() : null;
    final isCreator = _race!['isCreator'] as bool? ?? false;

    return Column(
      children: [
        // Countdown
        if (endsAt != null) _buildCountdown(endsAt),
        const SizedBox(height: 12),

        // Race track
        RetroCard(
          padding: const EdgeInsets.all(6),
          child: GoalTrack(
            height: 300,
            runners: [
              for (final p in participants)
                GoalTrackRunner(
                  name: p['stealthed'] == true
                      ? '???'
                      : (p['displayName'] as String? ?? '???'),
                  progress: targetSteps > 0 && p['totalSteps'] != null
                      ? ((p['totalSteps'] as int) / targetSteps)
                      : 0.0,
                  isUser: (p['userId'] as String?) == _myUserId,
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Leaderboard details
        RetroCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('RACE TO ',
                      style: PixelText.title(
                          size: 13, color: AppColors.textMid)),
                  Text(_formatSteps(targetSteps),
                      style: PixelText.title(
                          size: 13, color: AppColors.accent)),
                  Text(' STEPS',
                      style: PixelText.title(
                          size: 13, color: AppColors.textMid)),
                ],
              ),
              const SizedBox(height: 10),
              for (int i = 0; i < participants.length; i++)
                _buildLeaderboardRow(participants[i], i),
            ],
          ),
        ),

        // Powerup inventory bar
        if (_powerupData != null &&
            _powerupData!['enabled'] == true) ...[
          const SizedBox(height: 12),
          _buildInventoryBar(),
        ],

        // Activity feed
        if (_powerupData != null &&
            _powerupData!['enabled'] == true) ...[
          const SizedBox(height: 12),
          _buildFeedSection(),
        ],

        if (isCreator) ...[
          const SizedBox(height: 12),
          PillButton(
            label: 'INVITE MORE',
            variant: PillButtonVariant.secondary,
            fontSize: 13,
            fullWidth: true,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            onPressed: _isActing ? null : _inviteMore,
          ),
          const SizedBox(height: 10),
          PillButton(
            label: 'CANCEL RACE',
            variant: PillButtonVariant.accent,
            fontSize: 13,
            fullWidth: true,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            onPressed: _isActing ? null : _cancelRace,
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildInventoryBar() {
    final inventory = (_powerupData?['inventory'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        [];
    final slotCount = (_powerupData?['powerupSlots'] as int?) ?? 3;
    final hasExtraSlot = slotCount > 3;

    return RetroCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('POWERUPS',
              style: PixelText.title(size: 11, color: AppColors.textMid)),
          const SizedBox(height: 8),
          Row(
            children: List.generate(slotCount, (i) {
              final isExtraSlot = i >= 3;
              if (i < inventory.length) {
                final pw = inventory[i];
                final type = pw['type'] as String? ?? '';
                return Expanded(
                  child: GestureDetector(
                    onTap: _isActing ? null : () => _showPowerupActions(pw),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.parchmentDark,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isExtraSlot
                              ? AppColors.coinMid
                              : _rarityColors[pw['rarity']] ??
                                  AppColors.parchmentBorder,
                          width: isExtraSlot ? 2.5 : 2,
                        ),
                      ),
                      child: Column(
                        children: [
                          PowerupIcon(type: type, size: 22),
                          const SizedBox(height: 2),
                          Text(
                            _powerupNames[type] ?? type,
                            style: PixelText.title(
                                size: 8, color: AppColors.textDark),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              } else {
                return Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.parchmentDark.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isExtraSlot
                            ? AppColors.coinMid.withValues(alpha: 0.5)
                            : AppColors.parchmentBorder.withValues(alpha: 0.3),
                        width: isExtraSlot ? 2.5 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text('---',
                            style: PixelText.body(
                                size: 22, color: AppColors.textMid.withValues(alpha: 0.3))),
                        const SizedBox(height: 2),
                        Text(isExtraSlot ? 'Bonus' : 'Empty',
                            style: PixelText.title(
                                size: 8,
                                color: isExtraSlot
                                    ? AppColors.coinMid.withValues(alpha: 0.6)
                                    : AppColors.textMid.withValues(alpha: 0.3))),
                      ],
                    ),
                  ),
                );
              }
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedSection() {
    return RetroCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('ACTIVITY',
                  style: PixelText.title(size: 14, color: AppColors.textMid)),
              GestureDetector(
                onTap: _loadFeed,
                child: Icon(Icons.refresh,
                    size: 16, color: AppColors.textMid.withValues(alpha: 0.6)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_feedEvents.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('No powerup activity yet',
                  style: PixelText.body(
                      size: 14, color: AppColors.textMid.withValues(alpha: 0.6))),
            )
          else
            for (int i = 0; i < _feedEvents.length && i < 10; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PowerupIcon(type: _feedEvents[i]['powerupType'] as String? ?? '', size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _feedEvents[i]['description'] as String? ?? '',
                        style:
                            PixelText.body(size: 14, color: AppColors.textDark),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildCompletedContent() {
    final winner = _race!['winner'] as Map<String, dynamic>?;
    final participants = (_progress?['participants'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        (_race!['participants'] as List?)?.cast<Map<String, dynamic>>() ??
        [];
    final targetSteps = _race!['targetSteps'] as int? ?? 0;

    return Column(
      children: [
        // Winner banner
        RetroCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Text('RACE COMPLETE',
                  style:
                      PixelText.title(size: 13, color: AppColors.textMid)),
              const SizedBox(height: 8),
              if (winner != null) ...[
                Icon(Icons.emoji_events, size: 40, color: AppColors.coinMid),
                const SizedBox(height: 4),
                Text(
                  winner['displayName'] as String? ?? 'Unknown',
                  style: PixelText.title(
                      size: 22, color: AppColors.pillGreenDark),
                ),
                Text('WINNER',
                    style: PixelText.title(
                        size: 13, color: AppColors.textMid)),
              ] else
                Text('No winner',
                    style: PixelText.title(
                        size: 18, color: AppColors.textMid)),
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
        RetroCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('FINAL STANDINGS',
                  style:
                      PixelText.title(size: 13, color: AppColors.textMid)),
              const SizedBox(height: 10),
              for (int i = 0; i < participants.length; i++)
                _buildLeaderboardRow(participants[i], i),
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
        Icon(Icons.cancel_outlined,
            size: 48, color: AppColors.textMid.withValues(alpha: 0.6)),
        const SizedBox(height: 12),
        Text('This race was cancelled',
            style: PixelText.title(size: 18, color: AppColors.textMid)),
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

    return RetroCard(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _CountdownUnit(value: days, label: 'DAYS'),
          const SizedBox(width: 8),
          _CountdownUnit(value: hours, label: 'HRS'),
          const SizedBox(width: 8),
          _CountdownUnit(value: minutes, label: 'MIN'),
          const SizedBox(width: 8),
          _CountdownUnit(value: seconds, label: 'SEC'),
        ],
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
            child: Text(badgeText,
                style: PixelText.title(size: 12, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaderboardRow(Map<String, dynamic> p, int rank) {
    final name = p['displayName'] as String? ?? '???';
    final totalSteps = p['totalSteps'] as int?;
    final userId = p['userId'] as String? ?? '';
    final isMe = userId == _myUserId;
    final isStealthed = p['stealthed'] == true;

    final medals = ['1st', '2nd', '3rd'];
    final prefix = rank < 3 ? medals[rank] : '${rank + 1}.';

    // Find active effects on this participant
    final activeEffects = (_powerupData?['activeEffects'] as List?)
            ?.cast<Map<String, dynamic>>()
            .where((e) => e['targetUserId'] == userId)
            .toList() ??
        [];

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 45,
            child: Text(prefix,
                style: PixelText.title(size: 18, color: AppColors.textMid)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isStealthed ? '???' : (isMe ? '$name (you)' : name),
                  style: PixelText.body(
                    size: 18,
                    color: isStealthed
                        ? AppColors.textMid.withValues(alpha: 0.5)
                        : isMe
                            ? AppColors.accent
                            : AppColors.textDark,
                  ),
                ),
                if (activeEffects.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (final e in activeEffects)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: (e['onSelf'] == true ? AppColors.pillGreenDark : AppColors.error).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: e['onSelf'] == true ? AppColors.pillGreenDark : AppColors.error,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                PowerupIcon(type: e['type'] as String? ?? '', size: 10),
                                const SizedBox(width: 3),
                                Text(
                                  _powerupNames[e['type'] as String? ?? ''] ?? e['type'] as String? ?? '',
                                  style: PixelText.body(
                                    size: 10,
                                    color: e['onSelf'] == true ? AppColors.pillGreenDark : AppColors.error,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Text(
            isStealthed ? '???' : _formatSteps(totalSteps ?? 0),
            style: PixelText.number(
              size: 18,
              color: isStealthed
                  ? AppColors.textMid.withValues(alpha: 0.5)
                  : AppColors.textMid,
            ),
          ),
        ],
      ),
    );
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.woodDark,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            value.toString().padLeft(2, '0'),
            style: PixelText.number(size: 22, color: AppColors.parchment),
          ),
        ),
        const SizedBox(height: 4),
        Text(label,
            style: PixelText.title(size: 9, color: AppColors.textMid)),
      ],
    );
  }
}
