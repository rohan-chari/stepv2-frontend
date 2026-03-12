import 'package:flutter/material.dart';

/// A cute animated capybara that walks across the screen using a sprite sheet.
///
/// Uses `assets/images/capybara_walk_right.png` — a 384x64 sprite sheet
/// with 6 frames (64x64 each).
class WalkingCapybara extends StatefulWidget {
  final Duration walkDuration;
  final double size;

  const WalkingCapybara({
    super.key,
    this.walkDuration = const Duration(seconds: 10),
    this.size = 64,
  });

  @override
  State<WalkingCapybara> createState() => _WalkingCapybaraState();
}

class _WalkingCapybaraState extends State<WalkingCapybara>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  static const int _frameCount = 6;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.walkDuration,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final capySize = widget.size;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // Walk position across screen
        final xPos =
            -capySize + (screenWidth + capySize * 2) * _controller.value;

        // Cycle through sprite frames
        final frameIndex =
            (_controller.value * _frameCount * 8).floor() % _frameCount;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: xPos,
              top: 0,
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
          ],
        );
      },
    );
  }
}
