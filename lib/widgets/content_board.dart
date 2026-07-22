import 'package:flutter/material.dart';

import '../styles.dart';

/// Full-width section surface used by legacy tabs.
class ContentBoard extends StatelessWidget {
  const ContentBoard({
    super.key,
    required this.child,
    this.width = 340,
    this.expand = false,
  });

  final Widget child;
  final double width;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: expand ? null : width,
      height: expand ? double.infinity : null,
      decoration: BoxDecoration(
        color: AppColors.of(context).parchment,
        border: Border.all(color: AppColors.of(context).textDark, width: 2),
      ),
      child: ClipRect(
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: SizedBox(width: double.infinity, child: child),
            ),
          ],
        ),
      ),
    );
  }
}

class PixelSurfacePainter extends CustomPainter {
  const PixelSurfacePainter({required this.dotColor});

  final Color dotColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = dotColor;
    const step = 18.0;

    for (double y = 0; y < size.height; y += step) {
      final startX = (y ~/ step).isEven ? 0.0 : step / 2;
      for (double x = startX; x < size.width; x += step) {
        canvas.drawRect(Rect.fromLTWH(x, y, 2, 2), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant PixelSurfacePainter oldDelegate) =>
      oldDelegate.dotColor != dotColor;
}
