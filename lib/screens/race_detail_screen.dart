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

class _RaceDetailScreenState extends State<RaceDetailScreen> {
  final BackendApiService _api = BackendApiService();
  Map<String, dynamic>? _race;
  Map<String, dynamic>? _progress;
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
      setState(() => _progress = progress);

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

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF87CEEB), Color(0xFFB0E0F0), Color(0xFFD4F1F9)],
          ),
        ),
        child: Padding(
          padding: EdgeInsets.only(top: topInset),
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
                Text('\u{1F3C6}',
                    style: const TextStyle(fontSize: 40)),
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
                size: 14,
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
                style: PixelText.title(size: 9, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaderboardRow(Map<String, dynamic> p, int rank) {
    final name = p['displayName'] as String? ?? '???';
    final totalSteps = p['totalSteps'] as int? ?? 0;
    final userId = p['userId'] as String? ?? '';
    final isMe = userId == _myUserId;

    final medals = ['\u{1F947}', '\u{1F948}', '\u{1F949}'];
    final prefix = rank < 3 ? medals[rank] : '${rank + 1}.';

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(prefix,
                style: PixelText.title(size: 14, color: AppColors.textMid)),
          ),
          Expanded(
            child: Text(
              isMe ? '$name (you)' : name,
              style: PixelText.body(
                size: 14,
                color: isMe ? AppColors.accent : AppColors.textDark,
              ),
            ),
          ),
          Text(_formatSteps(totalSteps),
              style: PixelText.number(size: 14, color: AppColors.textMid)),
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
