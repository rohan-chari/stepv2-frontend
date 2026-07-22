import 'package:flutter/material.dart';

import '../styles.dart';
import 'content_board.dart';

/// Shared page background for non-home screens.
class GameBackground extends StatelessWidget {
  const GameBackground({
    super.key,
    required this.child,
    this.groundHeightFraction = 0.22,
  });

  final Widget child;
  final double groundHeightFraction;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.of(context).parchmentLight,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: PixelSurfacePainter(
                dotColor: AppColors.of(
                  context,
                ).parchmentDark.withValues(alpha: 0.32),
              ),
            ),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}
