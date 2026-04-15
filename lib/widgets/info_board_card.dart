import 'package:flutter/material.dart';

import '../styles.dart';
import 'game_container.dart';

/// A green, wooden-framed info board — same style as the home tab's
/// "Climbing the Boards" highlight. Used for hero sections that need to
/// stand out from the parchment cards around them.
class InfoBoardCard extends StatelessWidget {
  final String? badgeLabel;
  final String? title;
  final String? subtitle;
  final List<Widget> children;
  final EdgeInsets padding;
  final double titleSize;
  final double subtitleSize;
  final TextAlign textAlign;
  final CrossAxisAlignment crossAxisAlignment;

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

  static const _textShadows = [
    Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  @override
  Widget build(BuildContext context) {
    final bool centered = textAlign == TextAlign.center;

    return GameContainer(
      padding: EdgeInsets.zero,
      surfaceColor: AppColors.pillGreenDark,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.pillGreen, AppColors.pillGreenDark],
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: 0.10),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: padding,
                child: Column(
                  crossAxisAlignment: crossAxisAlignment,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (badgeLabel != null)
                      Align(
                        alignment: centered
                            ? Alignment.center
                            : Alignment.centerLeft,
                        child: InfoBoardBadge(label: badgeLabel!),
                      ),
                    if (badgeLabel != null &&
                        (title != null || subtitle != null))
                      const SizedBox(height: 8),
                    if (title != null)
                      Text(
                        title!,
                        textAlign: textAlign,
                        style: PixelText.title(
                          size: titleSize,
                          color: AppColors.parchmentLight,
                        ).copyWith(shadows: _textShadows),
                      ),
                    if (title != null && subtitle != null)
                      const SizedBox(height: 4),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        textAlign: textAlign,
                        style: PixelText.body(
                          size: subtitleSize,
                          color: AppColors.parchment,
                        ).copyWith(shadows: _textShadows),
                      ),
                    ...children,
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Gold pill badge used as a label on top of an [InfoBoardCard].
class InfoBoardBadge extends StatelessWidget {
  const InfoBoardBadge({
    super.key,
    required this.label,
    this.fontSize = 13,
  });

  final String label;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.pillGold, AppColors.pillGoldDark],
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.pillGoldShadow, width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: AppColors.pillGoldShadow,
            offset: Offset(0, 2),
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
