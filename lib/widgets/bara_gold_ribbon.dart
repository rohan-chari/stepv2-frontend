import 'package:flutter/material.dart';

import '../styles.dart';

/// Shared Gold identity chrome for catalog and wardrobe surfaces.
class BaraGoldRibbon extends StatelessWidget {
  const BaraGoldRibbon({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return DecoratedBox(
      key: const Key('bara-gold-ribbon'),
      decoration: BoxDecoration(
        color: colors.pillGold,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: colors.pillGoldShadow.withValues(alpha: .35),
            offset: const Offset(0, 2),
            blurRadius: 0,
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 7 : 9,
          vertical: compact ? 3 : 4,
        ),
        child: Text(
          'Bara Gold',
          style: PixelText.title(
            size: compact ? 9 : 10,
            color: colors.textDark,
          ),
        ),
      ),
    );
  }
}
