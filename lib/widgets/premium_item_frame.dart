import 'package:flutter/material.dart';

import '../styles.dart';

/// Compact Gold treatment for catalog/reward items. The outline carries the
/// premium state without obscuring the artwork; the marker is intentionally
/// small enough for shop tiles and reel cells.
class PremiumItemFrame extends StatelessWidget {
  const PremiumItemFrame({
    super.key,
    required this.child,
    this.label = 'Bara Gold',
    this.compact = false,
    this.centeredLabel = false,
    this.frameKey,
    this.labelKey,
  });

  final Widget child;
  final String label;
  final bool compact;
  final bool centeredLabel;
  final Key? frameKey;
  final Key? labelKey;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    if (centeredLabel) {
      return _CenteredPremiumItemFrame(
        label: label,
        frameKey: frameKey,
        labelKey: labelKey,
        child: child,
      );
    }
    final accent = colors.isDark ? colors.medalGold : colors.roofMid;
    final marker = colors.isDark ? colors.pillGoldShadow : colors.pillGold;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: accent, width: compact ? 1.5 : 2),
        borderRadius: BorderRadius.circular(compact ? 10 : 14),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          Positioned(
            top: compact ? 3 : 5,
            right: compact ? 3 : 5,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 5 : 7,
                vertical: compact ? 2 : 3,
              ),
              decoration: BoxDecoration(
                color: marker,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                label,
                style: PixelText.title(
                  size: compact ? 6.5 : 8,
                  color: colors.textLight,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CenteredPremiumItemFrame extends StatelessWidget {
  const _CenteredPremiumItemFrame({
    required this.child,
    required this.label,
    this.frameKey,
    this.labelKey,
  });

  final Widget child;
  final String label;
  final Key? frameKey;
  final Key? labelKey;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final accent = colors.isDark ? colors.medalGold : colors.pillGoldDark;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          DecoratedBox(
            key: frameKey,
            decoration: BoxDecoration(
              color: colors.parchment,
              border: Border.all(color: accent, width: 2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: child,
              ),
            ),
          ),
          Positioned(
            top: -8,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                key: labelKey,
                color: colors.parchment,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  label,
                  style: PixelText.title(
                    size: 9,
                    color: colors.isDark ? colors.textLight : colors.textDark,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
