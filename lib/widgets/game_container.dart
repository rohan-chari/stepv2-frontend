import 'package:flutter/material.dart';

import '../styles.dart';
import 'content_board.dart';

/// Blocky arcade container used across tabs, race details, and modals.
class GameContainer extends StatelessWidget {
  const GameContainer({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.frameColor,
    this.glowColor,
    this.borderRadius = 14,
    this.surfaceColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? frameColor;
  final Color? glowColor;
  final double borderRadius;
  final Color? surfaceColor;

  @override
  Widget build(BuildContext context) {
    final border =
        frameColor ?? AppColors.of(context).roofDark.withValues(alpha: 0.55);
    final surface = surfaceColor ?? AppColors.of(context).parchment;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: border, width: 2),
        // Game-piece language: a hard straight-down drop by default; callers
        // that pass glowColor (reward reveals) get a soft halo instead.
        boxShadow: [
          if (glowColor == null)
            const BoxShadow(
              color: Color(0x66000000),
              offset: Offset(0, 4),
              blurRadius: 0,
            )
          else
            BoxShadow(
              color: glowColor!.withValues(alpha: 0.45),
              blurRadius: 16,
              spreadRadius: 1,
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius - 2),
        child: Stack(
          children: [
            if (surfaceColor == null)
              Positioned.fill(
                child: CustomPaint(
                  painter: PixelSurfacePainter(
                    dotColor: AppColors.of(
                      context,
                    ).parchmentDark.withValues(alpha: 0.32),
                  ),
                ),
              ),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }
}
