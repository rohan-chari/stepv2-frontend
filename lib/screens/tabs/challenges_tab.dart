import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../styles.dart';
import '../../widgets/tab_layout.dart';
import '../challenge_detail_screen.dart';

class ChallengesTab extends StatelessWidget {
  final AuthService authService;
  final Map<String, dynamic>? currentChallenge;
  final VoidCallback onChallengeChanged;

  const ChallengesTab({
    super.key,
    required this.authService,
    required this.currentChallenge,
    required this.onChallengeChanged,
  });

  bool get _hasActiveChallenge =>
      currentChallenge != null && currentChallenge!['challenge'] != null;

  @override
  Widget build(BuildContext context) {
    return TabLayout(
      title: 'CHALLENGES',
      child: _hasActiveChallenge
          ? _buildActiveChallenge(context)
          : _buildEmptyState(),
    );
  }

  Widget _buildActiveChallenge(BuildContext context) {
    final challenge =
        currentChallenge!['challenge'] as Map<String, dynamic>? ?? {};
    final instances = currentChallenge!['instances'] as List? ?? [];

    return Column(
      children: [
        Text(
          'THIS WEEK\u2019S CHALLENGE',
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
        if (instances.isNotEmpty) ...[
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Container(
              height: 1,
              color: AppColors.parchmentBorder.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 8),
          for (final instance in instances)
            _buildInstanceRow(
              context,
              instance as Map<String, dynamic>,
              challenge,
            ),
        ],
      ],
    );
  }

  Widget _buildInstanceRow(
    BuildContext context,
    Map<String, dynamic> instance,
    Map<String, dynamic> challenge,
  ) {
    final myUserId = authService.userId ?? '';
    final userA = instance['userA'] as Map<String, dynamic>?;
    final userB = instance['userB'] as Map<String, dynamic>?;

    String friendName = '???';
    if (userA != null && userA['id'] != myUserId) {
      friendName = userA['displayName'] as String? ?? '???';
    } else if (userB != null) {
      friendName = userB['displayName'] as String? ?? '???';
    }

    final status = instance['status'] as String? ?? '';
    final stakeStatus = instance['stakeStatus'] as String? ?? '';

    String statusLabel;
    Color statusColor;
    if (status == 'ACTIVE' || stakeStatus == 'AGREED') {
      statusLabel = 'ACTIVE';
      statusColor = AppColors.pillGreen;
    } else {
      final proposedById = instance['proposedById'] as String? ?? '';
      final isIncoming = proposedById.isNotEmpty && proposedById != myUserId;
      statusLabel = isIncoming ? 'RESPOND' : 'WAITING';
      statusColor =
          isIncoming ? AppColors.pillTerra : AppColors.pillGold;
    }

    return GestureDetector(
      onTap: () {
        Navigator.of(context)
            .push<bool>(
              MaterialPageRoute(
                builder: (context) => ChallengeDetailScreen(
                  authService: authService,
                  instance: instance,
                  challenge: challenge,
                ),
              ),
            )
            .then((_) => onChallengeChanged());
      },
      child: Container(
        margin: const EdgeInsets.only(top: 8),
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
                'vs $friendName',
                style: PixelText.title(size: 14, color: AppColors.textDark),
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
          'NO ACTIVE CHALLENGE',
          style: PixelText.title(size: 16, color: AppColors.textMid),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          'Challenge a friend from\nthe Friends tab!',
          style: PixelText.body(size: 14, color: AppColors.textMid),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
