import 'dart:math';
import 'package:flutter/material.dart';
import '../styles.dart';

/// A wooden-framed parchment board for content areas.
/// Same aesthetic as TrailSign but without sway animation or pin tacks —
/// meant for larger, scrollable content.
class ContentBoard extends StatelessWidget {
  final Widget child;
  final double width;
  final bool expand;

  const ContentBoard({
    super.key,
    required this.child,
    this.width = 340,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    const px = 3.0;
    const frameThickness = px * 3;

    return Container(
      width: expand ? null : width,
      height: expand ? double.infinity : null,
      decoration: BoxDecoration(
        color: AppColors.woodDark,
        border: Border.all(color: AppColors.woodShadow, width: px),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _WoodGrainPainter(px: px),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(frameThickness),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.parchment,
                border: Border.all(
                  color: AppColors.parchmentBorder,
                  width: px,
                ),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _ParchmentTexturePainter(px: px),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: px * 4,
                      vertical: px * 4,
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: child,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontal wood-grain lines on the board frame.
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
          Rect.fromLTWH(0, y, size.width, px * 0.5), highlightPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Subtle noise/speckle texture on the parchment surface.
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
