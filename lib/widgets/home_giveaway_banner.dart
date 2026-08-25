import 'package:flutter/material.dart';

import '../styles.dart';

/// The single active referral-contest promotion on Home.
///
/// Its solid, quiet game-piece treatment is intentional: the configured copy
/// is the headline, while prize and time are supporting facts.
class HomeGiveawayBanner extends StatelessWidget {
  const HomeGiveawayBanner({
    super.key,
    required this.message,
    required this.coinPrize,
    required this.endsAt,
    required this.onTap,
  });

  final String message;
  final int coinPrize;
  final DateTime endsAt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final remaining = endsAt.difference(DateTime.now());
    if (remaining <= Duration.zero) return const SizedBox.shrink();
    final colors = AppColors.of(context);
    final countdown = _remainingLabel(remaining);
    final formattedPrize = _commas(coinPrize);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Semantics(
        button: true,
        label:
            '$message. $formattedPrize Bara coins. Contest ends in $countdown. View contest.',
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: const Key('home-giveaway-banner-tap'),
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Container(
              key: const Key('home-giveaway-banner'),
              padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
              decoration: BoxDecoration(
                color: colors.pillGold,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colors.woodDarker, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: colors.woodDarker.withValues(alpha: 0.34),
                    offset: const Offset(0, 5),
                    blurRadius: 0,
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: colors.parchment,
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.woodDarker, width: 2),
                    ),
                    child: Icon(
                      Icons.emoji_events_rounded,
                      color: colors.coinDark,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          message,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: PixelText.title(
                            size: 15,
                            color: colors.woodDarker,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Wrap(
                          spacing: 7,
                          runSpacing: 4,
                          children: [
                            _FactChip(
                              label: '$formattedPrize COINS',
                              colors: colors,
                            ),
                            _FactChip(
                              label: 'ENDS IN $countdown',
                              colors: colors,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    constraints: const BoxConstraints(minWidth: 52),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: colors.woodDarker,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'VIEW',
                      textAlign: TextAlign.center,
                      style: PixelText.pill(size: 10, color: colors.textLight),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _remainingLabel(Duration remaining) {
    final seconds = remaining.inSeconds.clamp(0, 999999999);
    final days = seconds ~/ Duration.secondsPerDay;
    final hours = (seconds % Duration.secondsPerDay) ~/ Duration.secondsPerHour;
    final minutes =
        (seconds % Duration.secondsPerHour) ~/ Duration.secondsPerMinute;
    if (days > 0) return '${days}D ${hours.toString().padLeft(2, '0')}H';
    if (hours > 0) return '${hours}H ${minutes.toString().padLeft(2, '0')}M';
    return '${minutes.clamp(1, 59)}M';
  }

  static String _commas(int value) => value.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
}

class _FactChip extends StatelessWidget {
  const _FactChip({required this.label, required this.colors});

  final String label;
  final AppPalette colors;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
    decoration: BoxDecoration(
      color: colors.parchment.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: colors.woodDarker.withValues(alpha: 0.45)),
    ),
    child: Text(
      label,
      style: PixelText.pill(size: 9, color: colors.woodDarker),
    ),
  );
}
