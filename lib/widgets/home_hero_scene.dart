import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

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
/// When [groundScrollSpeed] is non-zero the ground slides left (the mascot
/// walks in place) and the clouds drift the same way but much slower, so the
/// two layers read as parallax rather than one flat sheet.
///
/// Honors `MediaQuery.disableAnimations` by freezing the drift instead of
/// running the ambient ticker.
class HomeHeroScene extends StatefulWidget {
  const HomeHeroScene({
    super.key,
    required this.child,
    this.groundHeight = 86,
    this.skyAlignment = Alignment.bottomCenter,
    this.groundScrollSpeed = 0,
  });

  final Widget child;

  /// Height of the grass + dirt strip at the bottom of the scene.
  final double groundHeight;

  /// Logical pixels/second the ground strip slides to the LEFT, which reads as
  /// the (stationary) capybara walking forward. 0 freezes it. The strip is
  /// seam-tiled, so the scroll wraps every tile width with no visible jump.
  /// Also frozen when `MediaQuery.disableAnimations` is set.
  final double groundScrollSpeed;

  /// Controls how the wide sky artwork crops in unusually tall scenes.
  final AlignmentGeometry skyAlignment;

  /// Source dimensions of home_hero_ground.png (the course-strip crop); used
  /// to size each tile to [groundHeight] exactly.
  static const _groundSrcWidth = 1350.0;
  static const _groundSrcHeight = 164.0;

  @override
  State<HomeHeroScene> createState() => _HomeHeroSceneState();
}

class _HomeHeroSceneState extends State<HomeHeroScene>
    with TickerProviderStateMixin {
  late final AnimationController _ambient;

  /// Monotonic seconds since the scene mounted, driving the ground scroll.
  /// A raw ticker (rather than a repeating controller) keeps the phase
  /// continuous, so the wrap point never has to line up with a fixed period.
  final ValueNotifier<double> _groundPhase = ValueNotifier<double>(0);
  late final Ticker _groundTicker;

  @override
  void initState() {
    super.initState();
    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    );
    _groundTicker = createTicker((elapsed) {
      _groundPhase.value = elapsed.inMicroseconds / 1e6;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    precacheImage(AssetImage(AppThemeAssets.light.homeHeroSky), context);
    precacheImage(AssetImage(AppThemeAssets.night.homeHeroSky), context);
    precacheImage(AssetImage(AppThemeAssets.light.homeHeroGround), context);
    precacheImage(AssetImage(AppThemeAssets.night.homeHeroGround), context);
    precacheImage(AssetImage(AppThemeAssets.light.homeClouds), context);
    precacheImage(AssetImage(AppThemeAssets.night.homeClouds), context);
    if (MediaQuery.of(context).disableAnimations) {
      _ambient.stop();
      _ambient.value = 0.35;
      _groundTicker.stop();
    } else {
      if (!_ambient.isAnimating) {
        _ambient.repeat();
      }
      _syncGroundTicker();
    }
  }

  @override
  void didUpdateWidget(covariant HomeHeroScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.groundScrollSpeed != oldWidget.groundScrollSpeed) {
      _syncGroundTicker();
    }
  }

  void _syncGroundTicker() {
    if (!mounted) return;
    final wanted =
        widget.groundScrollSpeed != 0 &&
        !MediaQuery.of(context).disableAnimations;
    if (wanted && !_groundTicker.isActive) {
      _groundTicker.start();
    } else if (!wanted && _groundTicker.isActive) {
      _groundTicker.stop();
    }
  }

  @override
  void dispose() {
    _groundTicker.dispose();
    _groundPhase.dispose();
    _ambient.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final assets = AppThemeAssets.of(context);
    final transitionDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 250);
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
            child: AnimatedSwitcher(
              duration: transitionDuration,
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeOutCubic,
              layoutBuilder: (currentChild, previousChildren) => Stack(
                fit: StackFit.expand,
                children: [...previousChildren, ?currentChild],
              ),
              child: Image.asset(
                assets.homeHeroSky,
                key: ValueKey(assets.homeHeroSky),
                fit: BoxFit.cover,
                alignment: widget.skyAlignment,
                filterQuality: FilterQuality.none,
              ),
            ),
          ),
        ),
        // Generated cloud-atlas instances sit over the sky but under the
        // ground/child. Their asset changes with theme without resetting the
        // shared ambient controller or the five layout phases.
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          bottom: widget.groundHeight,
          child: LayoutBuilder(
            builder: (context, constraints) => AnimatedBuilder(
              animation: _ambient,
              builder: (context, _) => Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  for (var i = 0; i < _clouds.length; i++)
                    _CloudInstance(
                      key: ValueKey('home-cloud-$i'),
                      config: _clouds[i],
                      t: _ambient.value,
                      fieldSize: constraints.biggest,
                      assetPath: assets.homeClouds,
                      transitionDuration: transitionDuration,
                    ),
                ],
              ),
            ),
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
                final scrolls = widget.groundScrollSpeed != 0;
                // One spare tile so the strip stays covered while it slides
                // left by up to a full tile width.
                final tiles =
                    (constraints.maxWidth / tileW).ceil() + (scrolls ? 1 : 0);
                // OverflowBox: the last tile intentionally runs past the
                // right edge (ClipRect trims it) without a flex overflow.
                final strip = OverflowBox(
                  key: const Key('hero-ground-strip'),
                  maxWidth: double.infinity,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < tiles; i++)
                        Image.asset(
                          assets.homeHeroGround,
                          key: ValueKey('${assets.homeHeroGround}-$i'),
                          width: tileW,
                          height: widget.groundHeight,
                          fit: BoxFit.fill,
                          filterQuality: FilterQuality.none,
                        ),
                    ],
                  ),
                );
                if (!scrolls) return strip;
                return ValueListenableBuilder<double>(
                  valueListenable: _groundPhase,
                  child: strip,
                  builder: (context, seconds, child) {
                    // Wrap on the tile width: the crop is seam-aligned, so
                    // resetting by exactly one tile is invisible.
                    final dx = -((seconds * widget.groundScrollSpeed) % tileW);
                    return Transform.translate(
                      offset: Offset(dx, 0),
                      child: child,
                    );
                  },
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

typedef _CloudConfig = ({
  double y,
  double scale,
  int cycles,
  double phase,
  int atlasIndex,
});

/// How much of a cloud's nominal drift actually reaches the screen.
///
/// The raw `cycles` values (1–3 crossings per 60s ambient period) put the
/// fastest cloud at ~26 logical px/s on a phone-width scene — the exact speed
/// of the ground strip. A background layer moving as fast as the foreground is
/// not parallax; it flattens the scene. Scaling the whole set down leaves the
/// far layer at roughly an eighth to a third of the ground's speed, which is
/// the depth cue, while keeping the five clouds' relative spread.
const double _cloudDriftFactor = 0.35;

const List<_CloudConfig> _clouds = [
  (y: 0.42, scale: 0.74, cycles: 1, phase: 0.12, atlasIndex: 0),
  (y: 0.56, scale: 0.54, cycles: 2, phase: 0.38, atlasIndex: 1),
  (y: 0.66, scale: 0.67, cycles: 1, phase: 0.62, atlasIndex: 2),
  (y: 0.48, scale: 0.46, cycles: 3, phase: 0.80, atlasIndex: 1),
  (y: 0.72, scale: 0.58, cycles: 2, phase: 0.96, atlasIndex: 0),
];

class _CloudInstance extends StatelessWidget {
  const _CloudInstance({
    super.key,
    required this.config,
    required this.t,
    required this.fieldSize,
    required this.assetPath,
    required this.transitionDuration,
  });

  final _CloudConfig config;
  final double t;
  final Size fieldSize;
  final String assetPath;
  final Duration transitionDuration;

  @override
  Widget build(BuildContext context) {
    final cloudSize = 112.0 * config.scale;
    const span = 1.35;
    // Clouds drift LEFT, the SAME way the ground slides — that is what
    // parallax is. The mascot walks right, so the whole world moves left past
    // the camera; depth comes from the far layer moving *slower*, not from it
    // moving the other way. The previous version sent the clouds right, which
    // gave them a higher apparent speed than the ground and read as clouds
    // racing forwards in front of the capybara.
    final wrapped =
        ((config.phase - t * config.cycles * _cloudDriftFactor) % span + span) %
        span;
    final x = (wrapped - 0.18) * fieldSize.width;
    final y = fieldSize.height * config.y;
    return Positioned(
      left: x,
      top: y,
      width: cloudSize,
      height: cloudSize,
      child: ClipRect(
        child: AnimatedSwitcher(
          duration: transitionDuration,
          child: OverflowBox(
            key: ValueKey(assetPath),
            alignment: Alignment.centerLeft,
            minWidth: cloudSize * 3,
            maxWidth: cloudSize * 3,
            child: Transform.translate(
              offset: Offset(-cloudSize * config.atlasIndex, 0),
              child: Image.asset(
                assetPath,
                width: cloudSize * 3,
                height: cloudSize,
                fit: BoxFit.fill,
                filterQuality: FilterQuality.none,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Generated pixel-art hedge tiled across the horizon. Sized by height and
/// repeated horizontally — the same explicit-width tiling the hero scene's
/// ground strip uses, because `Image`'s own repeat sizing renders short on
/// high devicePixelRatio screens.
class HeroTreeline extends StatelessWidget {
  const HeroTreeline({super.key});

  static const _asset = 'assets/images/hero_treeline_day.png';
  static const _srcWidth = 1200.0;
  static const _srcHeight = 206.0;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tileW = _srcWidth * constraints.maxHeight / _srcHeight;
          final tiles = (constraints.maxWidth / tileW).ceil();
          return OverflowBox(
            maxWidth: double.infinity,
            alignment: Alignment.bottomLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < tiles; i++)
                  Image.asset(
                    _asset,
                    width: tileW,
                    height: constraints.maxHeight,
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.none,
                    errorBuilder: (_, _, _) => SizedBox(width: tileW),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
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
