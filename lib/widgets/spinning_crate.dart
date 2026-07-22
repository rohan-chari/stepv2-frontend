import 'dart:math';
import 'package:flutter/material.dart';

import '../styles.dart';

class SpinningCrate extends StatefulWidget {
  final double size;

  const SpinningCrate({super.key, this.size = 80});

  @override
  State<SpinningCrate> createState() => _SpinningCrateState();
}

class _SpinningCrateState extends State<SpinningCrate>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        // Subtle rock side to side
        final rock = sin(t * 2 * pi) * 0.05;

        return SizedBox(
          width: s * 1.5,
          height: s * 1.8,
          child: Center(
            child: Transform.rotate(
              angle: rock,
              child: _CrateFace(size: s),
            ),
          ),
        );
      },
    );
  }
}

/// Static (non-animated) crate, for dense lists where a per-row spin animation
/// would be distracting and wasteful. [filled] false renders a faded/empty
/// slot to represent "zero boxes". [queued] renders a dimmed crate with a small
/// clock badge to represent a box waiting for inventory space (inventory full).
class CrateIcon extends StatelessWidget {
  final double size;
  final bool filled;
  final bool queued;
  const CrateIcon({
    super.key,
    this.size = 20,
    this.filled = true,
    this.queued = false,
  });

  @override
  Widget build(BuildContext context) {
    final crate = _CrateFace(size: size);
    if (queued) {
      // Half-bright crate with a clock corner badge: a box you've earned but
      // can't hold yet because your slots are full.
      return SizedBox.square(
        dimension: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Opacity(opacity: 0.55, child: crate),
            Positioned(
              right: -size * 0.12,
              bottom: -size * 0.12,
              child: Container(
                width: size * 0.5,
                height: size * 0.5,
                decoration: BoxDecoration(
                  color: AppColors.of(context).pillGold,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.of(context).dirtDark,
                    width: 1,
                  ),
                ),
                child: Icon(
                  Icons.schedule,
                  size: size * 0.34,
                  color: AppColors.of(context).textDark,
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (filled) return crate;
    return Opacity(opacity: 0.3, child: crate);
  }
}

class _CrateFace extends StatelessWidget {
  final double size;
  const _CrateFace({required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _PixelCratePainter(),
        child: Center(
          child: Text(
            '?',
            style:
                PixelText.title(
                  size: size * 0.42,
                  color: AppColors.of(context).coinLight,
                ).copyWith(
                  shadows: [
                    Shadow(
                      color: AppColors.of(context).dirtDark,
                      offset: Offset(size * 0.035, size * 0.035),
                      blurRadius: 0,
                    ),
                  ],
                ),
          ),
        ),
      ),
    );
  }
}

class _PixelCratePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.shortestSide / 16;

    Rect r(double x, double y, double w, double h) =>
        Rect.fromLTWH(x * unit, y * unit, w * unit, h * unit);

    void fill(double x, double y, double w, double h, Color color) {
      canvas.drawRect(r(x, y, w, h), Paint()..color = color);
    }

    void stroke(double x, double y, double w, double h, Color color) {
      canvas.drawRect(
        r(x, y, w, h),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = max(1.5, unit * 0.7),
      );
    }

    fill(2, 2, 12, 12, AppColors.dirtMid);
    fill(2, 2, 12, 2, AppColors.dirtLight);
    fill(2, 12, 12, 2, AppColors.dirtDark);
    fill(2, 2, 2, 12, AppColors.dirtLight);
    fill(12, 2, 2, 12, AppColors.dirtDark);

    fill(3, 3, 10, 3, const Color(0xFFD79855));
    fill(3, 7, 10, 2, AppColors.dirtLight);
    fill(3, 10, 10, 3, const Color(0xFF8E5A32));

    fill(2, 6, 12, 1, AppColors.dirtDark);
    fill(2, 9, 12, 1, AppColors.dirtDark);
    fill(6, 2, 1, 12, AppColors.dirtDark);
    fill(9, 2, 1, 12, AppColors.dirtDark);

    fill(1, 1, 2, 2, AppColors.grassBright);
    fill(13, 1, 2, 2, AppColors.grassBright);
    fill(1, 13, 2, 2, AppColors.grassDark);
    fill(13, 13, 2, 2, AppColors.grassDark);

    fill(4, 4, 2, 1, const Color(0xFFFFC878));
    fill(10, 4, 1, 1, const Color(0xFFFFC878));
    fill(4, 11, 2, 1, const Color(0xFF6E4428));

    stroke(2, 2, 12, 12, AppColors.roofDark);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
