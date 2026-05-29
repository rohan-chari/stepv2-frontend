import 'package:flutter/material.dart';

import '../styles.dart';
import 'pill_button.dart';
import 'retro_card.dart';

/// Compact card for the pinned "Featured" strip on the Races tab. Leads with
/// the top-50% coin reward, shows a countdown + live racer count, and offers a
/// one-tap JOIN (which flips to VIEW once joined, or FULL at capacity).
class FeaturedRaceCard extends StatelessWidget {
  const FeaturedRaceCard({
    super.key,
    required this.name,
    required this.seedKind,
    required this.endsAt,
    required this.participantCount,
    required this.finishRewardPool,
    required this.isJoined,
    required this.isFull,
    required this.isJoining,
    required this.onJoin,
    required this.onView,
    this.width = 250,
  });

  final String name;
  final String? seedKind;
  final DateTime? endsAt;
  final int participantCount;
  final int finishRewardPool;
  final bool isJoined;
  final bool isFull;
  final bool isJoining;
  final VoidCallback onJoin;
  final VoidCallback onView;
  final double width;

  String get _cadenceLabel {
    switch (seedKind) {
      case 'DAILY_10K':
        return 'DAILY';
      case 'WEEKLY_50K':
        return 'WEEKLY';
      default:
        return 'FEATURED';
    }
  }

  String _countdownLabel() {
    final ends = endsAt;
    if (ends == null) return 'LIVE NOW';
    final remaining = ends.difference(DateTime.now());
    if (remaining.isNegative) return 'ENDING SOON';
    if (remaining.inDays > 0) {
      return 'ENDS IN ${remaining.inDays}d ${remaining.inHours.remainder(24)}h';
    }
    if (remaining.inHours > 0) {
      return 'ENDS IN ${remaining.inHours}h ${remaining.inMinutes.remainder(60)}m';
    }
    return 'ENDS IN ${remaining.inMinutes}m';
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: RetroCard(
        highlightColor: AppColors.accent,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      _cadenceLabel,
                      style: PixelText.title(size: 11, color: AppColors.accent),
                    ),
                    const Spacer(),
                    if (isJoined)
                      Text(
                        'JOINED',
                        style: PixelText.title(
                          size: 11,
                          color: AppColors.pillGreenDark,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  name,
                  style: PixelText.title(size: 17, color: AppColors.textDark),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                if (finishRewardPool > 0)
                  Row(
                    children: [
                      const Icon(
                        Icons.monetization_on_rounded,
                        size: 16,
                        color: AppColors.coinDark,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          'Top 50% win $finishRewardPool',
                          style: PixelText.title(
                            size: 13,
                            color: AppColors.coinDark,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 6),
                Text(
                  _countdownLabel(),
                  style: PixelText.body(size: 12, color: AppColors.textMid),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '$participantCount racing',
                  style: PixelText.body(size: 12, color: AppColors.textMid),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _buildCta(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCta() {
    if (isJoined) {
      return PillButton(
        label: 'VIEW',
        variant: PillButtonVariant.secondary,
        fontSize: 13,
        fullWidth: true,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        onPressed: onView,
      );
    }
    if (isFull) {
      return PillButton(
        label: 'FULL',
        variant: PillButtonVariant.secondary,
        fontSize: 13,
        fullWidth: true,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        onPressed: null,
      );
    }
    return PillButton(
      label: isJoining ? 'JOINING…' : 'JOIN',
      variant: PillButtonVariant.primary,
      fontSize: 13,
      fullWidth: true,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      onPressed: isJoining ? null : onJoin,
    );
  }
}
