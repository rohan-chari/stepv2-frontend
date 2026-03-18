import 'dart:math';
import 'package:flutter/material.dart';
import '../styles.dart';

class StepProgressRing extends StatefulWidget {
  final double progress;
  final Widget child;
  final double width;
  final double height;
  final double trackWidth;

  const StepProgressRing({
    super.key,
    required this.progress,
    required this.child,
    this.width = 240,
    this.height = 160,
    this.trackWidth = 6,
  });

  @override
  State<StepProgressRing> createState() => _StepProgressRingState();
}

class _StepProgressRingState extends State<StepProgressRing>
    with TickerProviderStateMixin {
  late AnimationController _spriteController;
  late AnimationController _fillController;
  late Animation<double> _fillAnimation;
  static const int _frameCount = 6;

  @override
  void initState() {
    super.initState();
    _spriteController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat();

    _fillController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _fillAnimation = CurvedAnimation(
      parent: _fillController,
      curve: Curves.easeOutCubic,
    );

    // Animate in on mount
    _fillController.forward();
  }

  @override
  void didUpdateWidget(StepProgressRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.progress != widget.progress) {
      _fillController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _spriteController.dispose();
    _fillController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final targetProgress = widget.progress.clamp(0.0, 1.0);
    const capySize = 32.0;

    const capyOverflow = capySize / 2 + 4;

    return Padding(
      padding: const EdgeInsets.all(capyOverflow),
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: AnimatedBuilder(
        animation: Listenable.merge([_fillAnimation, _spriteController]),
        builder: (context, _) {
          final currentProgress = targetProgress * _fillAnimation.value;

          // Capybara position on the ellipse
          final angle = -pi / 2 + (2 * pi * currentProgress);
          final rx = (widget.width - widget.trackWidth) / 2;
          final ry = (widget.height - widget.trackWidth) / 2;
          final cx = widget.width / 2 + rx * cos(angle) - capySize / 2;
          final cy = widget.height / 2 + ry * sin(angle) - capySize / 2;

          // Sprite frame — always animate walk cycle
          final frameIndex =
              (_spriteController.value * _frameCount).floor() % _frameCount;

          // Flip based on travel direction
          final goingLeft = cos(angle) < 0;

          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: Size(widget.width, widget.height),
                painter: _RingPainter(
                  progress: currentProgress,
                  trackWidth: widget.trackWidth,
                ),
              ),
              widget.child,
              if (currentProgress > 0)
                Positioned(
                  left: cx,
                  top: cy,
                  child: Transform(
                    alignment: Alignment.center,
                    transform: goingLeft
                        ? (Matrix4.identity()..scale(-1.0, 1.0, 1.0))
                        : Matrix4.identity(),
                    child: SizedBox(
                      width: capySize,
                      height: capySize,
                      child: ClipRect(
                        child: OverflowBox(
                          maxWidth: double.infinity,
                          alignment: Alignment.topLeft,
                          child: Transform.translate(
                            offset: Offset(-frameIndex * capySize, 0),
                            child: Image.asset(
                              'assets/images/capybara_walk_right.png',
                              width: capySize * _frameCount,
                              height: capySize,
                              filterQuality: FilterQuality.none,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final double trackWidth;

  _RingPainter({
    required this.progress,
    required this.trackWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      trackWidth / 2,
      trackWidth / 2,
      size.width - trackWidth,
      size.height - trackWidth,
    );

    // Background track
    final bgPaint = Paint()
      ..color = AppColors.parchmentBorder.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = trackWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawOval(rect, bgPaint);

    // Filled arc
    if (progress > 0) {
      final fillPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = trackWidth
        ..strokeCap = StrokeCap.round
        ..shader = const LinearGradient(
          colors: [AppColors.pillGreen, AppColors.pillGreenDark],
        ).createShader(rect);

      final sweepAngle = 2 * pi * progress.clamp(0.0, 1.0);
      canvas.drawArc(rect, -pi / 2, sweepAngle, false, fillPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
