import 'package:flutter/material.dart';

import '../styles.dart';
import '../utils/race_display.dart';
import 'arcade_fx.dart';
import 'pill_button.dart';
import 'race_ui.dart';

/// Compact card for the pinned "Featured" strip on the Races tab. Leads with
/// the minted coin reward (split across the top `finishRewardPlaces` finishers),
/// shows a countdown + live racer count, and offers a one-tap JOIN (which flips
/// to VIEW once joined, or FULL at capacity).
class FeaturedRaceCard extends StatelessWidget {
  const FeaturedRaceCard({
    super.key,
    required this.name,
    required this.seedKind,
    required this.endsAt,
    required this.participantCount,
    required this.finishRewardPool,
    this.finishRewardPlaces = 0,
    required this.isJoined,
    required this.isFull,
    required this.isJoining,
    required this.onJoin,
    required this.onView,
    this.isUpcoming = false,
    this.startsAt,
    this.width = 250,
  });

  final String name;
  final String? seedKind;
  final DateTime? endsAt;
  final int participantCount;
  final int finishRewardPool;
  // How many top places split the pool (server-computed, scales with field).
  // 0 when the backend didn't send it (older backend) — we then fall back to a
  // fraction-free label rather than the stale "Top 50%".
  final int finishRewardPlaces;
  final bool isJoined;
  final bool isFull;
  final bool isJoining;
  final VoidCallback onJoin;
  final VoidCallback onView;
  // Pre-registration variant: the next, not-yet-started seeded race a user can
  // opt into before it begins. Counts down to `startsAt` and the CTA is
  // OPT IN / YOU'RE IN / FULL instead of JOIN / VIEW.
  final bool isUpcoming;
  final DateTime? startsAt;
  final double width;

  // Coin-reward line. The pool is split across the top `finishRewardPlaces`
  // finishers, so name the actual place count rather than a fixed fraction. We
  // fall back to a fraction-free label when an older backend omits the count.
  String get _rewardLabel {
    if (finishRewardPlaces == 1) {
      return 'Winner wins $finishRewardPool';
    }
    if (finishRewardPlaces > 1) {
      return 'Top $finishRewardPlaces win $finishRewardPool';
    }
    return 'Top finishers win $finishRewardPool';
  }

  String get _cadenceLabel {
    if (isUpcoming) {
      switch (seedKind) {
        case 'DAILY_10K':
          return 'TOMORROW';
        case 'WEEKLY_50K':
          return 'NEXT WEEK';
        default:
          return 'UP NEXT';
      }
    }
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
    if (isUpcoming) {
      final starts = startsAt;
      if (starts == null) return 'STARTING SOON';
      final remaining = starts.difference(DateTime.now());
      if (remaining.isNegative) return 'STARTING SOON';
      if (remaining.inDays > 0) {
        return 'STARTS IN ${remaining.inDays}d ${remaining.inHours.remainder(24)}h';
      }
      if (remaining.inHours > 0) {
        return 'STARTS IN ${remaining.inHours}h ${remaining.inMinutes.remainder(60)}m';
      }
      return 'STARTS IN ${remaining.inMinutes}m';
    }
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
      child: Container(
        decoration: raceCardDecoration(),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Pill(
                  label: _cadenceLabel,
                  background: AppColors.pillGold,
                  fontSize: 11,
                ),
                const SizedBox(height: 8),
                Text(
                  raceDisplayName(seedKind, name),
                  textAlign: TextAlign.center,
                  style: PixelText.title(size: 17, color: AppColors.textDark),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                if (finishRewardPool > 0)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.monetization_on_rounded,
                        size: 16,
                        color: AppColors.coinDark,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          _rewardLabel,
                          textAlign: TextAlign.center,
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
                  textAlign: TextAlign.center,
                  style: PixelText.body(size: 12, color: AppColors.textMid),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  isUpcoming
                      ? '$participantCount joined'
                      : '$participantCount racing',
                  textAlign: TextAlign.center,
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
    const padding = EdgeInsets.symmetric(horizontal: 16, vertical: 11);
    if (isJoined) {
      // Upcoming: "YOU'RE IN" (you opted into the next race); live: "VIEW".
      return PillButton(
        label: isUpcoming ? "YOU'RE IN" : 'VIEW',
        variant: PillButtonVariant.secondary,
        fontSize: 13,
        fullWidth: true,
        padding: padding,
        onPressed: onView,
      );
    }
    if (isFull) {
      return PillButton(
        label: 'FULL',
        variant: PillButtonVariant.secondary,
        fontSize: 13,
        fullWidth: true,
        padding: padding,
        onPressed: null,
      );
    }
    // Upcoming: "OPT IN" (pre-register for the next race); live: "JOIN".
    final joinLabel = isUpcoming
        ? (isJoining ? 'OPTING IN…' : 'OPT IN')
        : (isJoining ? 'JOINING…' : 'JOIN');
    // The one actionable moment on the card gets the arcade glow.
    return PulseGlow(
      child: PillButton(
        label: joinLabel,
        variant: PillButtonVariant.primary,
        fontSize: 13,
        fullWidth: true,
        padding: padding,
        onPressed: isJoining ? null : onJoin,
      ),
    );
  }
}
