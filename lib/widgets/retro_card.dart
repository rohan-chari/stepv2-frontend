import 'dart:math';

import 'package:flutter/material.dart';
import '../styles.dart';

/// A thin retro bulletin-board-style card: wood frame outline with
/// parchment interior. Inspired by ContentBoard but much thinner.
class RetroCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? highlightColor;

  const RetroCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.highlightColor,
  });

  @override
  Widget build(BuildContext context) {
    final frameColor = highlightColor == null
        ? AppColors.woodDark
        : Color.lerp(highlightColor, AppColors.woodDark, 0.18)!;
    final borderColor = highlightColor == null
        ? AppColors.woodShadow
        : Color.lerp(highlightColor, Colors.black, 0.45)!;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppColors.woodShadow.withValues(alpha: 0.28),
            offset: const Offset(0, 3),
            blurRadius: 6,
          ),
          if (highlightColor != null)
            BoxShadow(
              color: highlightColor!.withValues(alpha: 0.25),
              spreadRadius: 1,
              blurRadius: 8,
            ),
        ],
      ),
      child: Container(
        decoration: BoxDecoration(
          color: frameColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 1),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: CustomPaint(painter: _RetroWoodGrainPainter()),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(2),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.parchment,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: AppColors.parchmentBorder.withValues(alpha: 0.85),
                    width: 1,
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CustomPaint(
                          painter: _RetroParchmentTexturePainter(),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      left: 8,
                      right: 8,
                      child: Container(
                        height: 1,
                        color: Colors.white.withValues(alpha: 0.25),
                      ),
                    ),
                    Padding(padding: padding, child: child),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RetroWoodGrainPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final grainPaint = Paint()
      ..color = AppColors.woodGrain.withValues(alpha: 0.28);
    final highlightPaint = Paint()
      ..color = AppColors.woodHighlight.withValues(alpha: 0.14);

    for (double y = 3; y < size.height; y += 6) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), grainPaint);
    }
    for (double y = 5; y < size.height; y += 10) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 0.5), highlightPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _RetroParchmentTexturePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(42);
    final dotPaint = Paint()
      ..color = AppColors.parchmentDark.withValues(alpha: 0.16);

    for (int i = 0; i < 40; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      canvas.drawRect(Rect.fromLTWH(x, y, 1.5, 1.5), dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
