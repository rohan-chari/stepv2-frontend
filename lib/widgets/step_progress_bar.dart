import 'package:flutter/material.dart';
import '../styles.dart';

class StepProgressBar extends StatefulWidget {
  final double progress;
  final double height;
  final double trackHeight;

  const StepProgressBar({
    super.key,
    required this.progress,
    this.height = 48,
    this.trackHeight = 48,
  });

  @override
  State<StepProgressBar> createState() => _StepProgressBarState();
}

class _StepProgressBarState extends State<StepProgressBar>
    with TickerProviderStateMixin {
  late AnimationController _spriteController;
  late AnimationController _fillController;
  late Animation<double> _fillAnimation;
  static const int _frameCount = 6;
  static const double _capySize = 44.0;

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

    _fillController.forward();
  }

  @override
  void didUpdateWidget(StepProgressBar oldWidget) {
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

    return AnimatedBuilder(
      animation: Listenable.merge([_fillAnimation, _spriteController]),
      builder: (context, _) {
        final currentProgress = targetProgress * _fillAnimation.value;
        final frameIndex =
            (_spriteController.value * _frameCount).floor() % _frameCount;

        return SizedBox(
          height: widget.height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final barWidth = constraints.maxWidth;
              // Capybara right edge aligns with fill edge (inside the green)
              final capyLeft =
                  (currentProgress * barWidth - _capySize).clamp(0.0, barWidth - _capySize);
              // Vertically center capybara inside the bar
              final capyTop = (widget.trackHeight - _capySize) / 2;

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // Track background
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.parchmentBorder.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(widget.trackHeight / 2),
                      ),
                    ),
                  ),
                  // Filled portion
                  if (currentProgress > 0)
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: currentProgress * barWidth,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.pillGreen, AppColors.pillGreenDark],
                          ),
                          borderRadius: BorderRadius.circular(widget.trackHeight / 2),
                        ),
                      ),
                    ),
                  // Capybara sprite
                  if (currentProgress > 0)
                    Positioned(
                      left: capyLeft,
                      top: capyTop,
                      child: SizedBox(
                        width: _capySize,
                        height: _capySize,
                        child: ClipRect(
                          child: OverflowBox(
                            maxWidth: double.infinity,
                            alignment: Alignment.topLeft,
                            child: Transform.translate(
                              offset: Offset(-frameIndex * _capySize, 0),
                              child: Image.asset(
                                'assets/images/capybara_walk_right.png',
                                width: _capySize * _frameCount,
                                height: _capySize,
                                filterQuality: FilterQuality.none,
                                fit: BoxFit.contain,
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
        );
      },
    );
  }
}
