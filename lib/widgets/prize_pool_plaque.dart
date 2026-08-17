import 'package:flutter/material.dart';

import '../models/race_prize_pool.dart';
import '../styles.dart';

/// The carved gold plaque that carries a pool figure: an "up to" number that
/// re-stamps itself whenever the field or the timeline changes, its own
/// arithmetic spelled out underneath so the number is never a mystery.
///
/// Extracted from `CreateRaceScreen` so the EDIT screen can show it too (race
/// timeline options §10.1 risk 6): a control that changes the pool without
/// showing the pool is the same class of lie as a stale duration label. The
/// markup and keys are unchanged from the create screen's original.
class PrizePoolPlaque extends StatelessWidget {
  const PrizePoolPlaque({
    super.key,
    required this.coins,
    required this.atMax,
    required this.derivation,
    this.footnote,
    this.coinsKey,
    this.derivationKey,
    this.maxKey,
  });

  final int coins;
  final bool atMax;
  final String derivation;

  /// Optional trailing line. Nothing sets it today, but the plaque keeps the
  /// slot for callers that still want one.
  final String? footnote;

  final Key? coinsKey;
  final Key? derivationKey;
  final Key? maxKey;

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: palette.coinLight.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: palette.coinDark.withValues(alpha: 0.45),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'PRIZE POOL',
                  style: PixelText.title(size: 12, color: palette.textMid),
                ),
              ),
              if (atMax)
                Container(
                  key: maxKey,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: palette.coinDark,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    'MAX',
                    style: PixelText.title(size: 9, color: Colors.white),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Image.asset(
                'assets/images/coin.png',
                width: 24,
                height: 24,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) =>
                    Icon(Icons.paid_rounded, size: 22, color: palette.coinDark),
              ),
              const SizedBox(width: 8),
              Text(
                'UP TO',
                style: PixelText.body(size: 10, color: palette.textMid),
              ),
              const SizedBox(width: 6),
              // Re-stamps with a quick punch on every change, so a bigger
              // field visibly pays more.
              Flexible(
                child: TweenAnimationBuilder<double>(
                  key: ValueKey(coins),
                  tween: Tween<double>(begin: 0.84, end: 1),
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutBack,
                  builder: (_, value, child) => Transform.scale(
                    scale: value,
                    alignment: Alignment.centerLeft,
                    child: child,
                  ),
                  child: Text(
                    formatPrizeCoins(coins),
                    key: coinsKey,
                    maxLines: 1,
                    style: PixelText.number(size: 28, color: palette.coinDark),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            derivation,
            key: derivationKey,
            style: PixelText.body(size: 11, color: palette.textMid),
          ),
          if (footnote != null && footnote!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              footnote!,
              style: PixelText.body(size: 10, color: palette.textMid),
            ),
          ],
        ],
      ),
    );
  }
}
