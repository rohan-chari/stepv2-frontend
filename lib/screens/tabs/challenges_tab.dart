import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/backend_api_service.dart';
import '../../styles.dart';
import '../../widgets/error_toast.dart';
import '../../widgets/info_toast.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/tab_layout.dart';
import '../challenge_detail_screen.dart';
import '../stake_picker_screen.dart';

class ChallengesTab extends StatefulWidget {
  final AuthService authService;
  final Map<String, dynamic>? currentChallenge;
  final List<Map<String, dynamic>> friendsSteps;
  final VoidCallback onChallengeChanged;
  final VoidCallback? onOpenFriendsTab;
  final Future<void> Function()? onRefresh;
  final DateTime Function()? now;

  const ChallengesTab({
    super.key,
    required this.authService,
    required this.currentChallenge,
    required this.friendsSteps,
    required this.onChallengeChanged,
    this.onOpenFriendsTab,
    this.onRefresh,
    this.now,
  });

  @override
  State<ChallengesTab> createState() => _ChallengesTabState();
}

class _ChallengesTabState extends State<ChallengesTab> {
  final BackendApiService _api = BackendApiService();
  bool _showFriendPicker = false;
  bool _isInitiating = false;
  Timer? _countdownTimer;
  late DateTime _countdownNow;

  bool get _hasActiveChallenge =>
      widget.currentChallenge != null &&
      widget.currentChallenge!['challenge'] != null;

  DateTime get _now => (widget.now ?? DateTime.now).call();

  DateTime? get _challengeEndsAt {
    final rawValue = widget.currentChallenge?['endsAt'] as String?;
    if (rawValue == null || rawValue.isEmpty) return null;
    return DateTime.tryParse(rawValue)?.toLocal();
  }

  String get _myUserId => widget.authService.userId ?? '';

  List<Map<String, dynamic>> _getAvailableFriends() {
    final instances = widget.currentChallenge?['instances'] as List? ?? [];
    final challengedIds = <String>{};
    for (final i in instances) {
      final inst = i as Map<String, dynamic>;
      final aId =
          inst['userAId'] as String? ??
          (inst['userA'] as Map<String, dynamic>?)?['id'] as String? ??
          '';
      final bId =
          inst['userBId'] as String? ??
          (inst['userB'] as Map<String, dynamic>?)?['id'] as String? ??
          '';
      challengedIds.add(aId);
      challengedIds.add(bId);
    }

    return widget.friendsSteps.where((f) {
      final id = f['id'] as String? ?? '';
      return !challengedIds.contains(id);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _countdownNow = _now;
    _syncCountdownTimer();
  }

  @override
  void didUpdateWidget(covariant ChallengesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    _countdownNow = _now;
    _syncCountdownTimer();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  /// Categorize instances into incoming, outgoing, and active
  Map<String, List<Map<String, dynamic>>> _categorizeInstances() {
    final instances = widget.currentChallenge?['instances'] as List? ?? [];
    final incoming = <Map<String, dynamic>>[];
    final outgoing = <Map<String, dynamic>>[];
    final active = <Map<String, dynamic>>[];

    for (final i in instances) {
      final inst = i as Map<String, dynamic>;
      final status = inst['status'] as String? ?? '';
      final stakeStatus = inst['stakeStatus'] as String? ?? '';

      if (status == 'ACTIVE' || stakeStatus == 'AGREED') {
        active.add(inst);
      } else {
        final proposedById = inst['proposedById'] as String? ?? '';
        if (proposedById.isNotEmpty && proposedById != _myUserId) {
          incoming.add(inst);
        } else {
          outgoing.add(inst);
        }
      }
    }

    return {'incoming': incoming, 'outgoing': outgoing, 'active': active};
  }

  Future<void> _startChallenge(String friendId, String friendName) async {
    final stakeId = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (context) => StakePickerScreen(
          authService: widget.authService,
          friendName: friendName,
        ),
      ),
    );

    if (stakeId == null || !mounted) return;

    setState(() => _isInitiating = true);

    try {
      final token = widget.authService.authToken;
      if (token == null || token.isEmpty) return;

      await _api.initiateChallenge(
        identityToken: token,
        friendUserId: friendId,
        stakeId: stakeId,
      );

      if (mounted) {
        setState(() {
          _isInitiating = false;
          _showFriendPicker = false;
        });
        widget.onChallengeChanged();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isInitiating = false);
        showErrorToast(context, e.toString());
      }
    }
  }

  void _syncCountdownTimer() {
    _countdownTimer?.cancel();

    if (!_hasActiveChallenge || _challengeEndsAt == null) {
      return;
    }

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _countdownNow = _now;
      });
    });
  }

  String _formatCountdown(Duration duration) {
    final safeDuration =
        duration.isNegative ? Duration.zero : duration;
    final days = safeDuration.inDays;
    final hours = safeDuration.inHours.remainder(24);
    final minutes = safeDuration.inMinutes.remainder(60);
    final seconds = safeDuration.inSeconds.remainder(60);

    return '${days}D ${hours}H ${minutes}M ${seconds}S';
  }

  void _handleChallengeFriendTap(List<Map<String, dynamic>> availableFriends) {
    if (widget.friendsSteps.isEmpty) {
      widget.onOpenFriendsTab?.call();
      showInfoToast(context, 'Add some friends first on the Friends tab.');
      return;
    }

    if (availableFriends.isEmpty) {
      showInfoToast(context, 'All friends already challenged this week!');
      return;
    }

    setState(() => _showFriendPicker = true);
  }

  @override
  Widget build(BuildContext context) {
    return TabLayout(
      title: 'CHALLENGES',
      onRefresh: widget.onRefresh,
      child: _hasActiveChallenge
          ? _buildActiveChallenge(context)
          : _buildEmptyState(),
    );
  }

  Widget _buildActiveChallenge(BuildContext context) {
    final challenge =
        widget.currentChallenge!['challenge'] as Map<String, dynamic>? ?? {};
    final categories = _categorizeInstances();
    final incoming = categories['incoming']!;
    final outgoing = categories['outgoing']!;
    final active = categories['active']!;
    final availableFriends = _getAvailableFriends();
    final hasAnyInstances =
        incoming.isNotEmpty || outgoing.isNotEmpty || active.isNotEmpty;
    final challengeEndsAt = _challengeEndsAt;

    return Column(
      children: [
        // Challenge header
        Text(
          'THIS WEEK\u2019S COMPETITION',
          style: PixelText.title(size: 14, color: AppColors.accent),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          challenge['title'] as String? ?? '',
          style: PixelText.title(size: 18, color: AppColors.textDark),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          challenge['description'] as String? ?? '',
          style: PixelText.body(color: AppColors.textMid),
          textAlign: TextAlign.center,
        ),
        if (challengeEndsAt != null) ...[
          const SizedBox(height: 12),
          _buildCountdownBoard(challengeEndsAt),
        ],

        // Instance tables by category
        if (incoming.isNotEmpty) ...[
          _buildDivider(),
          _buildSectionHeader('INCOMING'),
          _buildInstanceTable(context, incoming, challenge),
        ],

        if (active.isNotEmpty) ...[
          _buildDivider(),
          _buildSectionHeader('ACTIVE'),
          _buildInstanceTable(context, active, challenge),
        ],

        if (outgoing.isNotEmpty) ...[
          _buildDivider(),
          _buildSectionHeader('SENT'),
          _buildInstanceTable(context, outgoing, challenge),
        ],

        // Empty state
        if (!hasAnyInstances) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                Icon(Icons.emoji_events, size: 32, color: AppColors.textMid),
                const SizedBox(height: 8),
                Text(
                  'No challenges yet \u2014 time to start one!',
                  style: PixelText.body(color: AppColors.textMid),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],

        // Start a challenge button
        if (widget.authService.displayName != null) ...[
          _buildDivider(),
          if (!_showFriendPicker) ...[
            PillButton(
              label: 'CHALLENGE A FRIEND',
              variant: PillButtonVariant.primary,
              fontSize: 14,
              fullWidth: true,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              onPressed: () => _handleChallengeFriendTap(availableFriends),
            ),
            if (widget.friendsSteps.isNotEmpty && availableFriends.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'All friends already challenged this week!',
                  style: PixelText.body(color: AppColors.textMid),
                  textAlign: TextAlign.center,
                ),
              ),
          ] else
            _buildFriendPicker(availableFriends),
        ],
      ],
    );
  }

  Widget _buildCountdownBoard(DateTime endsAt) {
    final remaining = endsAt.difference(_countdownNow);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'CHALLENGE END: ',
          style: PixelText.title(size: 17.5, color: AppColors.textMid),
        ),
        Text(
          _formatCountdown(remaining),
          style: PixelText.number(size: 17.5, color: AppColors.textDark),
        ),
      ],
    );
  }

  Widget _buildDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Container(
        height: 1,
        color: AppColors.parchmentBorder.withValues(alpha: 0.5),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: PixelText.title(size: 12, color: AppColors.textMid),
        ),
      ),
    );
  }

  Widget _buildFriendPicker(List<Map<String, dynamic>> friends) {
    if (_isInitiating) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: CircularProgressIndicator(color: AppColors.accent),
        ),
      );
    }

    return Column(
      children: [
        Text(
          'PICK A FRIEND',
          style: PixelText.title(size: 14, color: AppColors.textMid),
        ),
        const SizedBox(height: 8),
        Table(
          columnWidths: const {
            0: FlexColumnWidth(),
            1: IntrinsicColumnWidth(),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          border: TableBorder(
            horizontalInside: BorderSide(
              color: AppColors.parchmentBorder.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          children: [
            for (int i = 0; i < friends.length; i++)
              _buildFriendPickerTableRow(friends[i], i),
          ],
        ),
        const SizedBox(height: 12),
        PillButton(
          label: 'CANCEL',
          variant: PillButtonVariant.secondary,
          fontSize: 12,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          onPressed: () => setState(() => _showFriendPicker = false),
        ),
      ],
    );
  }

  TableRow _buildFriendPickerTableRow(Map<String, dynamic> friend, int index) {
    final id = friend['id'] as String? ?? '';
    final name = friend['displayName'] as String? ?? '???';

    return TableRow(
      decoration: BoxDecoration(
        color: index.isOdd
            ? AppColors.accent.withValues(alpha: 0.07)
            : Colors.transparent,
      ),
      children: [
        TableCell(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _startChallenge(id, name),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: Text(
                name,
                style: PixelText.body(size: 18, color: AppColors.textDark),
              ),
            ),
          ),
        ),
        TableCell(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _startChallenge(id, name),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: Icon(Icons.chevron_right, size: 22, color: AppColors.textMid),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInstanceTable(
    BuildContext context,
    List<Map<String, dynamic>> instances,
    Map<String, dynamic> challenge,
  ) {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(),
        1: IntrinsicColumnWidth(),
        2: FixedColumnWidth(36),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      border: TableBorder(
        horizontalInside: BorderSide(
          color: AppColors.parchmentBorder.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      children: [
        for (int i = 0; i < instances.length; i++)
          _buildInstanceTableRow(context, instances[i], challenge, i),
      ],
    );
  }

  TableRow _buildInstanceTableRow(
    BuildContext context,
    Map<String, dynamic> instance,
    Map<String, dynamic> challenge,
    int index,
  ) {
    final instanceId = instance['id'] as String? ?? '';
    final userA = instance['userA'] as Map<String, dynamic>?;
    final userB = instance['userB'] as Map<String, dynamic>?;

    String friendName = '???';
    if (userA != null && userA['id'] != _myUserId) {
      friendName = userA['displayName'] as String? ?? '???';
    } else if (userB != null) {
      friendName = userB['displayName'] as String? ?? '???';
    }

    final status = instance['status'] as String? ?? '';
    final stakeStatus = instance['stakeStatus'] as String? ?? '';
    final proposedById = instance['proposedById'] as String? ?? '';
    final isIncoming = proposedById.isNotEmpty && proposedById != _myUserId;

    final proposedStake = instance['proposedStake'] as Map<String, dynamic>?;
    final agreedStake = instance['stake'] as Map<String, dynamic>?;
    final stakeName =
        agreedStake?['name'] as String? ??
        proposedStake?['name'] as String? ??
        '';

    String statusLabel;
    if (status == 'ACTIVE' || stakeStatus == 'AGREED') {
      statusLabel = 'ACTIVE';
    } else if (isIncoming) {
      statusLabel = 'ACCEPT';
    } else {
      statusLabel = 'WAITING';
    }

    void onTap() {
      Navigator.of(context)
          .push<bool>(
            MaterialPageRoute(
              builder: (context) => ChallengeDetailScreen(
                authService: widget.authService,
                instance: instance,
                challenge: challenge,
              ),
            ),
          )
          .then((_) => widget.onChallengeChanged());
    }

    return TableRow(
      decoration: BoxDecoration(
        color: index.isOdd
            ? AppColors.accent.withValues(alpha: 0.07)
            : Colors.transparent,
      ),
      children: [
        TableCell(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'vs $friendName',
                    style:
                        PixelText.title(size: 18, color: AppColors.textDark),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (stakeName.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      stakeName,
                      style: PixelText.body(
                          size: 14, color: AppColors.textMid),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        TableCell(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Text(
                statusLabel,
                style:
                    PixelText.title(size: 16, color: AppColors.textDark),
                textAlign: TextAlign.right,
              ),
            ),
          ),
        ),
        TableCell(
          child: GestureDetector(
            onTap: () => _showChallengeMenu(instanceId, friendName),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Icon(Icons.more_horiz, size: 22, color: AppColors.textMid),
            ),
          ),
        ),
      ],
    );
  }

  void _showChallengeMenu(String instanceId, String friendName) {
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
              'vs $friendName',
              style: PixelText.title(size: 18, color: AppColors.textDark),
            ),
            const SizedBox(height: 16),
            PillButton(
              label: 'CANCEL CHALLENGE',
              variant: PillButtonVariant.accent,
              fontSize: 13,
              fullWidth: true,
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              onPressed: () async {
                Navigator.of(context).pop();
                await _cancelChallenge(instanceId);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _cancelChallenge(String instanceId) async {
    try {
      final token = widget.authService.authToken;
      if (token == null || token.isEmpty) return;

      await BackendApiService().cancelChallenge(
        identityToken: token,
        instanceId: instanceId,
      );

      if (!mounted) return;
      widget.onChallengeChanged();
    } catch (e) {
      if (!mounted) return;
      showErrorToast(
          context, 'Couldn\u2019t cancel challenge. Please try again.');
    }
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(Icons.emoji_events, size: 32, color: AppColors.textMid),
          const SizedBox(height: 8),
          Text(
            'No active challenges \u2014 time to start one!',
            style: PixelText.body(size: 13, color: AppColors.textMid),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
