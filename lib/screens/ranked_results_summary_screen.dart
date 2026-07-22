import 'dart:ui';

import 'package:flutter/material.dart';

import '../styles.dart';
import '../utils/race_participant_display.dart';
import '../widgets/celebration_confetti.dart';
import '../widgets/game_container.dart';
import '../widgets/home_chrome.dart';
import '../widgets/pill_button.dart';
import '../widgets/spinning_coin.dart';
import '../widgets/tier_badge.dart';

/// Blurred-backdrop popup summarizing the user's most recently settled ranked
/// week — the "you got promoted" moment, surfaced proactively on app open from
/// any tab. The sibling of [RaceResultsSummaryScreen]: same transparent
/// Material + [BackdropFilter] pattern, pushed via `PageRouteBuilder(opaque:
/// false)` with a ~250ms fade by the caller.
///
/// [result] is the `lastWeek` map from `/ranked/v2`. Reads every field
/// defensively: it may come from a backend version newer or older than this
/// build.
class RankedResultsSummaryScreen extends StatelessWidget {
  const RankedResultsSummaryScreen({super.key, required this.result});

  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context) {
    final resultTier = rankedTierFromKey(result['resultTier'] as String?);
    final outcome = result['outcome'] as String?;
    final finalRank = (result['finalRank'] as num?)?.toInt();
    final cohortSize = (result['cohortSize'] as num?)?.toInt() ?? 0;
    final coins =
        ((result['rewardCoins'] as num?)?.toInt() ?? 0) +
        ((result['promotionCoins'] as num?)?.toInt() ?? 0);

    final (headline, accent) = switch (outcome) {
      'PROMOTE' => ('Promoted to ${resultTier.label}!', resultTier.color),
      'DEMOTE' => (
        'Moved down to ${resultTier.label}',
        AppColors.of(context).textMid,
      ),
      _ => ('Held ${resultTier.label}', resultTier.color),
    };

    final rankText = finalRank == null
        ? null
        : cohortSize > 0
        ? '${formatOrdinal(finalRank)} of $cohortSize'
        : formatOrdinal(finalRank);

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 2.5, sigmaY: 2.5),
              child: ColoredBox(
                color: AppColors.of(context).roofDark.withValues(alpha: 0.54),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(14, 18, 14, 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: GameContainer(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                    frameColor: AppColors.of(context).accent,
                    surfaceColor: AppColors.of(context).parchmentLight,
                    glowColor: AppColors.of(context).coinMid,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'RANKED WEEK',
                          textAlign: TextAlign.center,
                          style: HomeText.display(
                            size: 28,
                            color: AppColors.of(context).ink,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TierMedal(tier: resultTier, size: 72),
                        const SizedBox(height: 10),
                        Text(
                          headline,
                          textAlign: TextAlign.center,
                          style: PixelText.title(size: 18, color: accent),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.of(context).parchmentDark,
                            border: Border.all(
                              color: AppColors.of(context).coinDark,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (rankText != null)
                                _StatRow(
                                  icon: Icons.leaderboard_rounded,
                                  iconColor: AppColors.of(context).textMid,
                                  label: 'YOU FINISHED',
                                  value: rankText.toUpperCase(),
                                ),
                              if (rankText != null && coins > 0)
                                const SizedBox(height: 6),
                              if (coins > 0)
                                _StatRow(
                                  leading: const SpinningCoin(size: 18),
                                  label: 'PAYOUT',
                                  value: '+$coins',
                                  valueColor: AppColors.of(context).coinDark,
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'You start next week in ${resultTier.label}.',
                          textAlign: TextAlign.center,
                          style: PixelText.body(
                            size: 12,
                            color: AppColors.of(context).textMid,
                          ),
                        ),
                        const SizedBox(height: 18),
                        PillButton(
                          label: 'NICE',
                          variant: PillButtonVariant.primary,
                          fullWidth: true,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (outcome == 'PROMOTE')
            const Positioned.fill(child: CelebrationConfetti()),
        ],
      ),
    );
  }
}

/// One labelled stat line inside the summary card: an icon (or [leading]
/// widget), a label, and a right-aligned value.
class _StatRow extends StatelessWidget {
  const _StatRow({
    this.icon,
    this.iconColor,
    this.leading,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData? icon;
  final Color? iconColor;
  final Widget? leading;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        leading ??
            Icon(
              icon,
              size: 18,
              color: iconColor ?? AppColors.of(context).textMid,
            ),
        const SizedBox(width: 6),
        Text(
          label,
          style: PixelText.body(size: 11, color: AppColors.of(context).textMid),
        ),
        const Spacer(),
        Text(
          value,
          style: PixelText.number(
            size: 14,
            color: valueColor ?? AppColors.of(context).textDark,
          ),
        ),
      ],
    );
  }
}
