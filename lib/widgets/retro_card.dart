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
    final border =
        highlightColor ?? AppColors.roofDark.withValues(alpha: 0.55);
    final fill = highlightColor == null
        ? AppColors.parchment
        : Color.lerp(highlightColor, AppColors.parchment, 0.82)!;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border, width: 2),
        // Game-piece hard drop, matching the redesigned tabs' cards.
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            offset: Offset(0, 4),
            blurRadius: 0,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
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
