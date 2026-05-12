import 'package:flutter/material.dart';

import '../styles.dart';
import 'content_board.dart';

class ArcadePageBackground extends StatelessWidget {
  const ArcadePageBackground({
    super.key,
    this.child,
    this.headerHeight = 132,
    this.backgroundColor = AppColors.parchmentLight,
    this.headerColor = AppColors.accent,
  });

  final Widget? child;
  final double headerHeight;
  final Color backgroundColor;
  final Color headerColor;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;

    return ColoredBox(
      color: backgroundColor,
      child: Stack(
        children: [
          const Positioned.fill(
            child: CustomPaint(painter: PixelSurfacePainter()),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: topInset + headerHeight,
            child: ColoredBox(
              color: headerColor,
              child: const CustomPaint(painter: ArcadeCheckerPainter()),
            ),
          ),
          if (child != null) Positioned.fill(child: child!),
        ],
      ),
    );
  }
}
