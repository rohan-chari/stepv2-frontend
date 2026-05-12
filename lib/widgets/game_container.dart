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
    this.borderRadius = 8,
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
    final border = frameColor ?? AppColors.textDark;
    final surface = surfaceColor ?? AppColors.parchment;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: border, width: 2),
        boxShadow: [
          BoxShadow(
            color: (glowColor ?? border).withValues(alpha: 0.18),
            offset: const Offset(4, 4),
            blurRadius: 0,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius - 2),
        child: Stack(
          children: [
            if (surfaceColor == null)
              const Positioned.fill(
                child: CustomPaint(painter: PixelSurfacePainter()),
              ),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }
}
