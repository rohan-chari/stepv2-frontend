import 'dart:math';
import 'package:flutter/material.dart';
import '../styles.dart';

/// A rich, beveled wood-frame container with parchment interior.
/// Replaces RetroCard for sections that need more visual weight.
class GameContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? frameColor;
  final Color? glowColor;
  final double borderRadius;
  final Color? surfaceColor;

  const GameContainer({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.frameColor,
    this.glowColor,
    this.borderRadius = 10,
    this.surfaceColor,
  });

  @override
  Widget build(BuildContext context) {
    const px = 2.5;
    final frame = frameColor ?? AppColors.woodDark;
    final surface = surfaceColor ?? AppColors.parchment;
    final surfaceBorder = surfaceColor ?? AppColors.parchmentBorder;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius + 2),
        boxShadow: [
          BoxShadow(
            color: AppColors.woodShadow.withValues(alpha: 0.45),
            offset: const Offset(0, 4),
            blurRadius: 8,
          ),
          if (glowColor != null)
            BoxShadow(
              color: glowColor!.withValues(alpha: 0.35),
              spreadRadius: 2,
              blurRadius: 10,
            ),
        ],
      ),
      child: Container(
        decoration: BoxDecoration(
          color: frame,
          borderRadius: BorderRadius.circular(borderRadius + 2),
          border: Border.all(color: AppColors.woodShadow, width: px * 0.8),
        ),
        child: Stack(
          children: [
            // Wood grain on the frame
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(borderRadius),
                child: CustomPaint(painter: _WoodGrainPainter(px: px)),
              ),
            ),
            // Inner parchment surface
            Padding(
              padding: const EdgeInsets.all(px * 2.5),
              child: Container(
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(borderRadius - 2),
                  border: Border.all(
                    color: surfaceBorder,
                    width: px * 0.6,
                  ),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: Stack(
                    children: [
                      // Parchment texture (only on parchment surface)
                      if (surfaceColor == null)
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius:
                                BorderRadius.circular(borderRadius - 3),
                            child: CustomPaint(
                              painter: _ParchmentTexturePainter(px: px),
                            ),
                          ),
                        ),
                      // Top-edge bevel highlight
                      Positioned(
                        top: 0,
                        left: px * 2,
                        right: px * 2,
                        child: Container(
                          height: 1,
                          decoration: BoxDecoration(
                            color: AppColors.woodHighlight.withValues(
                              alpha: 0.3,
                            ),
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ),
                      // Content
                      Padding(padding: padding, child: child),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WoodGrainPainter extends CustomPainter {
  final double px;
  _WoodGrainPainter({required this.px});

  @override
  void paint(Canvas canvas, Size size) {
    final grainPaint = Paint()
      ..color = AppColors.woodGrain.withValues(alpha: 0.35);
    final highlightPaint = Paint()
      ..color = AppColors.woodHighlight.withValues(alpha: 0.18);

    for (double y = px * 3; y < size.height; y += px * 4) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, px), grainPaint);
    }
    for (double y = px * 5; y < size.height; y += px * 7) {
      canvas.drawRect(
        Rect.fromLTWH(0, y, size.width, px * 0.5),
        highlightPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ParchmentTexturePainter extends CustomPainter {
  final double px;
  _ParchmentTexturePainter({required this.px});

  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(42);
    final dotPaint = Paint()
      ..color = AppColors.parchmentDark.withValues(alpha: 0.18);

    for (int i = 0; i < 50; i++) {
      final x = (rng.nextDouble() * size.width / px).floor() * px;
      final y = (rng.nextDouble() * size.height / px).floor() * px;
      canvas.drawRect(Rect.fromLTWH(x, y, px, px), dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
