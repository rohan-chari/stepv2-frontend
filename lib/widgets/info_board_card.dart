import 'package:flutter/material.dart';

import '../styles.dart';
import 'game_container.dart';

/// Dark arcade hero panel for sections that need emphasis.
class InfoBoardCard extends StatelessWidget {
  const InfoBoardCard({
    super.key,
    this.badgeLabel,
    this.title,
    this.subtitle,
    this.children = const [],
    this.padding = const EdgeInsets.fromLTRB(14, 12, 14, 14),
    this.titleSize = 18,
    this.subtitleSize = 13,
    this.textAlign = TextAlign.center,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  });

  final String? badgeLabel;
  final String? title;
  final String? subtitle;
  final List<Widget> children;
  final EdgeInsets padding;
  final double titleSize;
  final double subtitleSize;
  final TextAlign textAlign;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    final centered = textAlign == TextAlign.center;

    return GameContainer(
      padding: EdgeInsets.zero,
      frameColor: AppColors.accent,
      surfaceColor: AppColors.accent,
      child: CustomPaint(
        painter: const ArcadeCheckerPainter(),
        child: Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: crossAxisAlignment,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (badgeLabel != null)
                Align(
                  alignment: centered ? Alignment.center : Alignment.centerLeft,
                  child: InfoBoardBadge(label: badgeLabel!),
                ),
              if (badgeLabel != null && (title != null || subtitle != null))
                const SizedBox(height: 8),
              if (title != null)
                Text(
                  title!,
                  textAlign: textAlign,
                  style: PixelText.title(
                    size: titleSize,
                    color: AppColors.parchmentLight,
                  ),
                ),
              if (title != null && subtitle != null) const SizedBox(height: 4),
              if (subtitle != null)
                Text(
                  subtitle!,
                  textAlign: textAlign,
                  style: PixelText.body(
                    size: subtitleSize,
                    color: AppColors.parchment,
                  ),
                ),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class InfoBoardBadge extends StatelessWidget {
  const InfoBoardBadge({super.key, required this.label, this.fontSize = 13});

  final String label;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.pillGold,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.pillGoldShadow, width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: AppColors.pillGoldShadow,
            offset: Offset(2, 2),
            blurRadius: 0,
          ),
        ],
      ),
      child: Text(
        label,
        style: PixelText.pill(size: fontSize, color: AppColors.textDark),
      ),
    );
  }
}
