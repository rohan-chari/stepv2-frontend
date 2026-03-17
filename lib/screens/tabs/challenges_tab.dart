import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../styles.dart';
import '../../widgets/content_board.dart';
import '../../widgets/trail_sign.dart';
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
    final boardWidth = MediaQuery.of(context).size.width - 48;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(top: 24, left: 24, right: 24, bottom: 120),
        child: Center(
          child: Column(
            children: [
              TrailSign(
                width: boardWidth,
                child: Text(
                  'CHALLENGES',
                  style: PixelText.title(size: 24, color: AppColors.textDark),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 16),
              if (_hasActiveChallenge)
                _buildActiveChallenge(context, boardWidth)
              else
                _buildEmptyState(boardWidth),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveChallenge(BuildContext context, double width) {
    final challenge =
        currentChallenge!['challenge'] as Map<String, dynamic>? ?? {};
    final instances = currentChallenge!['instances'] as List? ?? [];

    return Column(
      children: [
        ContentBoard(
          width: width,
          child: Column(
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
            ],
          ),
        ),
        // Show instances
        for (final instance in instances) ...[
          const SizedBox(height: 12),
          _buildInstanceRow(context, instance as Map<String, dynamic>, challenge),
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
      statusColor = AppColors.accent;
    } else {
      final proposedById = instance['proposedById'] as String? ?? '';
      final isIncoming = proposedById.isNotEmpty && proposedById != myUserId;
      statusLabel = isIncoming ? 'RESPOND' : 'WAITING';
      statusColor =
          isIncoming ? const Color(0xFFE05040) : Colors.orange.shade800;
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
      child: ContentBoard(
        width: MediaQuery.of(context).size.width - 48,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'vs $friendName',
                    style:
                        PixelText.title(size: 14, color: AppColors.textDark),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                statusLabel,
                style: PixelText.button(size: 11, color: statusColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(double width) {
    return ContentBoard(
      width: width,
      child: Column(
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
      ),
    );
  }
}
