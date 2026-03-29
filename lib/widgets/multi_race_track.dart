import 'package:flutter/material.dart';

import '../styles.dart';

class MultiRaceTrack extends StatelessWidget {
  final List<Map<String, dynamic>> participants;
  final int targetSteps;
  final String? currentUserId;

  const MultiRaceTrack({
    super.key,
    required this.participants,
    required this.targetSteps,
    this.currentUserId,
  });

  static const _runnerColors = [
    AppColors.pillGreenDark,
    AppColors.accent,
    AppColors.skyBand1,
    AppColors.pillTerraDark,
    AppColors.coinDark,
    AppColors.pineMid,
    AppColors.pillGoldDark,
    AppColors.error,
    AppColors.roofMid,
    AppColors.woodDark,
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (int i = 0; i < participants.length; i++) ...[
          _buildLane(participants[i], i),
          if (i < participants.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildLane(Map<String, dynamic> participant, int index) {
    final totalSteps = participant['totalSteps'] as int? ?? 0;
    final progress = targetSteps > 0
        ? (totalSteps / targetSteps).clamp(0.0, 1.0)
        : 0.0;
    final displayName = participant['displayName'] as String? ?? '???';
    final userId = participant['userId'] as String? ?? '';
    final isMe = userId == currentUserId;
    final color = _runnerColors[index % _runnerColors.length];
    final initials = displayName.isNotEmpty
        ? displayName.substring(0, displayName.length >= 2 ? 2 : 1).toUpperCase()
        : '??';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              displayName,
              style: PixelText.title(
                size: 12,
                color: isMe ? AppColors.accent : AppColors.textDark,
              ),
            ),
            const Spacer(),
            Text(
              _formatNumber(totalSteps),
              style: PixelText.number(size: 12, color: AppColors.textMid),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 28,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final trackWidth = constraints.maxWidth;
              final runnerLeft = progress * (trackWidth - 28);

              return Stack(
                children: [
                  // Track background
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.parchmentDark,
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  // Progress fill
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: progress * trackWidth,
                    child: Container(
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  // Finish line
                  Positioned(
                    right: 0,
                    top: 2,
                    bottom: 2,
                    child: Container(
                      width: 3,
                      decoration: BoxDecoration(
                        color: AppColors.textMid.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  // Runner avatar
                  Positioned(
                    left: runnerLeft,
                    top: 0,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isMe ? AppColors.accent : Colors.white,
                          width: isMe ? 2.5 : 1.5,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        initials,
                        style: PixelText.title(size: 9, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  static String _formatNumber(int n) {
    if (n >= 1000) {
      return '${(n / 1000).toStringAsFixed(n % 1000 == 0 ? 0 : 1)}k';
    }
    return '$n';
  }
}
