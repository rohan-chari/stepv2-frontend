import 'dart:math';
import 'package:flutter/material.dart';
import '../styles.dart';

/// A pixel-art wooden billboard panel. Content sits on a parchment
/// surface pinned inside the board frame.
class TrailSign extends StatefulWidget {
  final Widget child;
  final double width;
  final bool showTopRightPin;

  const TrailSign({
    super.key,
    required this.child,
    this.width = 300,
    this.showTopRightPin = true,
  });

  @override
  State<TrailSign> createState() => _TrailSignState();
}

class _TrailSignState extends State<TrailSign>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sway;

  @override
  void initState() {
    super.initState();
    _sway = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    _sway.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const px = 3.0;
    final boardWidth = widget.width;
    const frameThickness = px * 3;

    return AnimatedBuilder(
      animation: _sway,
      builder: (context, _) {
        final angle = sin(_sway.value * 2 * pi) * 0.004;

        return Transform.rotate(
          angle: angle,
          alignment: Alignment.center,
          child: Container(
            width: boardWidth,
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
                        Positioned(
                          top: px * 2,
                          left: px * 2,
                          child: _PinTack(px: px),
                        ),
                        if (widget.showTopRightPin)
                          Positioned(
                            top: px * 2,
                            right: px * 2,
                            child: _PinTack(px: px),
                          ),
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: px * 5,
                            vertical: px * 5,
                          ),
                          child: SizedBox(
                            width: double.infinity,
                            child: widget.child,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ────────────────────────────────────────────────
//  Pin tack / thumbtack widget
// ────────────────────────────────────────────────

class _PinTack extends StatelessWidget {
  final double px;
  const _PinTack({required this.px});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: px * 3,
      height: px * 3,
      decoration: const BoxDecoration(
        color: AppColors.pinMetal,
      ),
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            child: Container(
              width: px,
              height: px,
              color: AppColors.pinHighlight,
            ),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              width: px,
              height: px,
              color: AppColors.pinShadow,
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────
//  Custom Painters
// ────────────────────────────────────────────────

/// Horizontal wood-grain lines on the board frame.
class _WoodGrainPainter extends CustomPainter {
  final double px;

  _WoodGrainPainter({required this.px});

  @override
  void paint(Canvas canvas, Size size) {
    final grainPaint = Paint()..color = AppColors.woodGrain.withValues(alpha: 0.35);
    final highlightPaint = Paint()..color = AppColors.woodHighlight.withValues(alpha: 0.18);

    for (double y = px * 3; y < size.height; y += px * 4) {
      canvas.drawRect(
        Rect.fromLTWH(0, y, size.width, px),
        grainPaint,
      );
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

/// Subtle noise/speckle texture on the parchment surface.
class _ParchmentTexturePainter extends CustomPainter {
  final double px;

  _ParchmentTexturePainter({required this.px});

  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(77);
    final dotPaint = Paint()..color = AppColors.parchmentDark.withValues(alpha: 0.18);

    for (int i = 0; i < 30; i++) {
      final x = (rng.nextDouble() * size.width / px).floor() * px;
      final y = (rng.nextDouble() * size.height / px).floor() * px;
      canvas.drawRect(
        Rect.fromLTWH(x, y, px, px),
        dotPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
