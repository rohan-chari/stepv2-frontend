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
    this.skyAlignment = Alignment.bottomCenter,
  });

  final Widget child;

  /// Height of the grass + dirt strip at the bottom of the scene.
  final double groundHeight;

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
    precacheImage(AssetImage(AppThemeAssets.light.homeHeroSky), context);
    precacheImage(AssetImage(AppThemeAssets.night.homeHeroSky), context);
    precacheImage(AssetImage(AppThemeAssets.light.homeHeroGround), context);
    precacheImage(AssetImage(AppThemeAssets.night.homeHeroGround), context);
    precacheImage(AssetImage(AppThemeAssets.light.homeClouds), context);
    precacheImage(AssetImage(AppThemeAssets.night.homeClouds), context);
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
    final wrapped = ((config.phase - t * config.cycles) % span + span) % span;
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
