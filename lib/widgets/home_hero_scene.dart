import 'package:flutter/material.dart';

import '../styles.dart';

/// Ambient pixel-world backdrop for the home hero.
///
/// Both art layers are generated/derived assets, never hand-drawn (CLAUDE.md
/// rule): `home_hero_sky.png` is Codex-imagegen pixel art (banded sky + sun,
/// deliberately empty elsewhere so the HUD stays readable), and
/// `home_hero_ground.png` is a seam-aligned crop of the course scene's
/// grass-and-dirt strip, tiled horizontally at exactly [groundHeight] so the
/// capybara's ground anchoring stays pixel-exact on every screen size. The
/// only painted element is the pair of drifting clouds (explicitly
/// user-approved), kept below the step-count HUD so they never cross it.
///
/// Honors `MediaQuery.disableAnimations` by freezing the drift instead of
/// running the ambient ticker.
class HomeHeroScene extends StatefulWidget {
  const HomeHeroScene({
    super.key,
    required this.child,
    this.groundHeight = 86,
  });

  final Widget child;

  /// Height of the grass + dirt strip at the bottom of the scene.
  final double groundHeight;

  /// Top-edge color of the sky artwork; painted behind the status bar so the
  /// scene bleeds seamlessly to the screen edge.
  static const skyTopColor = Color(0xFF0089FB);

  /// Source dimensions of home_hero_ground.png (the course-strip crop); used
  /// to size each tile to [groundHeight] exactly.
  static const _groundSrcWidth = 1350.0;
  static const _groundSrcHeight = 164.0;

  @override
  State<HomeHeroScene> createState() => _HomeHeroSceneState();
}

class _HomeHeroSceneState extends State<HomeHeroScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ambient;

  @override
  void initState() {
    super.initState();
    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _ambient.stop();
      _ambient.value = 0.35;
    } else if (!_ambient.isAnimating) {
      _ambient.repeat();
    }
  }

  @override
  void dispose() {
    _ambient.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Sky artwork. It extends a little behind the grass fringe so the
        // transparent gaps between grass blades show sky, not a void.
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          bottom: widget.groundHeight - 20,
          child: ClipRect(
            child: Image.asset(
              'assets/images/home_hero_sky.png',
              fit: BoxFit.cover,
              alignment: Alignment.bottomCenter,
              filterQuality: FilterQuality.none,
            ),
          ),
        ),
        // Drifting clouds sit over the sky but under the ground/child.
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          bottom: widget.groundHeight,
          child: AnimatedBuilder(
            animation: _ambient,
            builder: (context, _) =>
                CustomPaint(painter: _DriftCloudsPainter(t: _ambient.value)),
          ),
        ),
        // Ground strip: the course scene's grass+dirt crop, tiled to exactly
        // [groundHeight] tall. Each tile is explicitly sized — Image's
        // `scale`/repeat sizing proved unreliable across devicePixelRatios
        // (rendered ~1/3 short on 3x devices, leaking backdrop below).
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: widget.groundHeight,
          child: ClipRect(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final tileW =
                    HomeHeroScene._groundSrcWidth *
                    widget.groundHeight /
                    HomeHeroScene._groundSrcHeight;
                final tiles = (constraints.maxWidth / tileW).ceil();
                // OverflowBox: the last tile intentionally runs past the
                // right edge (ClipRect trims it) without a flex overflow.
                return OverflowBox(
                  maxWidth: double.infinity,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < tiles; i++)
                        Image.asset(
                          'assets/images/home_hero_ground.png',
                          width: tileW,
                          height: widget.groundHeight,
                          fit: BoxFit.fill,
                          filterQuality: FilterQuality.none,
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

/// Paints the two slow drifting clouds over the sky artwork. They live in the
/// band between the step-count HUD and the horizon so they never cross the
/// number. [t] is a looping 0..1 ambient clock.
class _DriftCloudsPainter extends CustomPainter {
  const _DriftCloudsPainter({required this.t});

  final double t;

  // (yFrac of sky, scale, horizontal cycles per loop, phase)
  static const _clouds = [
    (0.58, 0.9, 1.0, 0.15),
    (0.72, 0.6, 2.0, 0.62),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (final (yFrac, scale, cycles, phase) in _clouds) {
      // Wrap over a span slightly wider than the screen so clouds fully exit
      // before re-entering. Integer cycle counts keep the loop seamless.
      const span = 1.3;
      final xFrac = ((phase + t * cycles) % span) - (span - 1) / 2 - 0.1;
      _paintCloud(canvas, Offset(xFrac * size.width, size.height * yFrac), scale);
    }
  }

  void _paintCloud(Canvas canvas, Offset origin, double scale) {
    final white = Paint()..color = AppColors.cloudWhite;
    final shadow = Paint()..color = AppColors.cloudShadow;
    RRect blob(double dx, double dy, double w, double h) {
      return RRect.fromRectAndRadius(
        Rect.fromLTWH(
          origin.dx + dx * scale,
          origin.dy + dy * scale,
          w * scale,
          h * scale,
        ),
        Radius.circular(5 * scale),
      );
    }

    canvas.drawRRect(blob(0, 14, 58, 13), shadow);
    canvas.drawRRect(blob(0, 10, 58, 13), white);
    canvas.drawRRect(blob(9, 2, 34, 13), white);
    canvas.drawRRect(blob(18, -5, 18, 11), white);
  }

  @override
  bool shouldRepaint(covariant _DriftCloudsPainter oldDelegate) =>
      oldDelegate.t != t;
}

/// A number that counts up to [value] (and re-animates between values on
/// refresh). Settles instantly when animations are disabled.
class CountUpText extends StatelessWidget {
  const CountUpText({
    super.key,
    required this.value,
    required this.style,
    required this.format,
    this.duration = const Duration(milliseconds: 900),
  });

  final int value;
  final TextStyle style;
  final String Function(int value) format;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final disable = MediaQuery.of(context).disableAnimations;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value.toDouble()),
      duration: disable ? Duration.zero : duration,
      curve: Curves.easeOutCubic,
      builder: (context, animated, _) =>
          Text(format(animated.round()), style: style),
    );
  }
}
