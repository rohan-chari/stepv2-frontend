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

  const ChallengesTab({
    super.key,
    required this.authService,
    required this.currentChallenge,
    required this.friendsSteps,
    required this.onChallengeChanged,
    this.onOpenFriendsTab,
    this.onRefresh,
  });

  @override
  State<ChallengesTab> createState() => _ChallengesTabState();
}

class _ChallengesTabState extends State<ChallengesTab> {
  final BackendApiService _api = BackendApiService();
  bool _showFriendPicker = false;
  bool _isInitiating = false;

  bool get _hasActiveChallenge =>
      widget.currentChallenge != null &&
      widget.currentChallenge!['challenge'] != null;

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

  void _handleChallengeFriendTap(List<Map<String, dynamic>> availableFriends) {
    if (widget.friendsSteps.isEmpty) {
      widget.onOpenFriendsTab?.call();
      showInfoToast(context, 'Add some friends first on the Friends tab.');
      return;
    }

    if (availableFriends.isEmpty) return;

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
          style: PixelText.body(size: 13, color: AppColors.textMid),
          textAlign: TextAlign.center,
        ),

        // Incoming challenges
        if (incoming.isNotEmpty) ...[
          _buildDivider(),
          _buildSectionHeader('INCOMING'),
          for (final inst in incoming)
            _buildInstanceRow(context, inst, challenge),
        ],

        // Active challenges
        if (active.isNotEmpty) ...[
          _buildDivider(),
          _buildSectionHeader('ACTIVE'),
          for (final inst in active)
            _buildInstanceRow(context, inst, challenge),
        ],

        // Outgoing challenges
        if (outgoing.isNotEmpty) ...[
          _buildDivider(),
          _buildSectionHeader('SENT'),
          for (final inst in outgoing)
            _buildInstanceRow(context, inst, challenge),
        ],

        // Empty state
        if (!hasAnyInstances && availableFriends.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'No challenges yet this week',
            style: PixelText.body(size: 13, color: AppColors.textMid),
            textAlign: TextAlign.center,
          ),
        ],

        // Start a challenge button
        if ((widget.friendsSteps.isEmpty || availableFriends.isNotEmpty) &&
            widget.authService.displayName != null) ...[
          _buildDivider(),
          if (!_showFriendPicker)
            PillButton(
              label: 'CHALLENGE A FRIEND',
              variant: PillButtonVariant.primary,
              fontSize: 14,
              fullWidth: true,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              onPressed: () => _handleChallengeFriendTap(availableFriends),
            )
          else
            _buildFriendPicker(availableFriends),
        ],
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
      padding: const EdgeInsets.only(bottom: 8),
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
          style: PixelText.title(size: 13, color: AppColors.textMid),
        ),
        const SizedBox(height: 8),
        for (final friend in friends) _buildFriendPickerRow(friend),
        const SizedBox(height: 8),
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

  Widget _buildFriendPickerRow(Map<String, dynamic> friend) {
    final id = friend['id'] as String? ?? '';
    final name = friend['displayName'] as String? ?? '???';

    return GestureDetector(
      onTap: () => _startChallenge(id, name),
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.parchmentLight,
          border: Border.all(color: AppColors.parchmentBorder),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                name,
                style: PixelText.title(size: 14, color: AppColors.textDark),
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: AppColors.textMid),
          ],
        ),
      ),
    );
  }

  Widget _buildInstanceRow(
    BuildContext context,
    Map<String, dynamic> instance,
    Map<String, dynamic> challenge,
  ) {
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

    // Determine stake name for display
    final proposedStake = instance['proposedStake'] as Map<String, dynamic>?;
    final agreedStake = instance['stake'] as Map<String, dynamic>?;
    final stakeName =
        agreedStake?['name'] as String? ??
        proposedStake?['name'] as String? ??
        '';

    String statusLabel;
    Color statusColor;
    if (status == 'ACTIVE' || stakeStatus == 'AGREED') {
      statusLabel = 'ACTIVE';
      statusColor = AppColors.pillGreen;
    } else if (isIncoming) {
      statusLabel = 'ACCEPT';
      statusColor = AppColors.accent;
    } else {
      statusLabel = 'WAITING';
      statusColor = AppColors.pillGold;
    }

    return GestureDetector(
      onTap: () {
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
      },
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.parchmentLight,
          border: Border.all(color: AppColors.parchmentBorder),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'vs $friendName',
                    style: PixelText.title(size: 14, color: AppColors.textDark),
                  ),
                  if (stakeName.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      stakeName,
                      style: PixelText.body(size: 11, color: AppColors.textMid),
                    ),
                  ],
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                statusLabel,
                style: PixelText.pill(size: 11, color: statusColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Column(
      children: [
        const SizedBox(height: 8),
        Text(
          'NO ACTIVE COMPETITION',
          style: PixelText.title(size: 16, color: AppColors.textMid),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          'Check back next week!',
          style: PixelText.body(size: 14, color: AppColors.textMid),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
