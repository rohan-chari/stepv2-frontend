import 'package:flutter/material.dart';

import '../styles.dart';
import 'content_board.dart';

/// Lightweight repeated-item surface aligned with the homepage redesign.
class RetroCard extends StatelessWidget {
  const RetroCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.highlightColor,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color? highlightColor;

  @override
  Widget build(BuildContext context) {
    final border = highlightColor ?? AppColors.parchmentBorder;
    final fill = highlightColor == null
        ? AppColors.parchment
        : Color.lerp(highlightColor, AppColors.parchment, 0.82)!;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border, width: 2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Stack(
          children: [
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
