import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Animated fire aura FX that rings a character avatar to signal a high step
/// multiplier on the race-detail leaderboard.
///
/// The sprite is a RING with a hollow centre, so the caller draws it IN FRONT
/// of the avatar: the face reads through the hole while the flame wraps the
/// avatar's border instead of hiding behind it.
///
/// Driven by a Codex-generated sprite sheet (`assets/images/fx/fire_aura.png`,
/// a 576x96 horizontal sheet of six 96x96 flicker frames — same layout as the
/// capybara walk sheet). [tier] drives INTENSITY, not size: the flicker speeds
/// up, the flame is graded toward white-hot, a heat-haze pulse grows, and a
/// bloom appears underneath. A 2x is a calm orange ring; an 11x roars.
/// Honors [MediaQuery.disableAnimations]: motion freezes on a single frame,
/// while the colour grade and bloom (which carry the tier meaning) remain.
class FireAura extends StatefulWidget {
  const FireAura({super.key, required this.size, required this.tier});

  /// Side length of the (square) sprite frame. Note this is the FRAME, not the
  /// visible ring — see the hole geometry below before positioning it.
  final double size;

  /// Multiplier tier = floor(multiplier). Only meaningful for tiers >= 2 (the
  /// caller renders nothing at 1x). Intensity saturates at [maxIntensityTier].
  final int tier;

  static const _asset = 'assets/images/fx/fire_aura.png';
  static const _frameCount = 6;

  /// Tier at which every intensity ramp reaches full. Above this a 20x looks
  /// like an 11x, which is fine — by then it is already maxed out visually.
  static const maxIntensityTier = 8;

  /// Geometry of the ring's HOLE inside a frame, as fractions of the frame box.
  ///
  /// Measured by FLOOD-FILLING the enclosed void in the sprite's alpha channel
  /// (averaged across all six frames). Do not re-derive these from a bounding
  /// box of transparent pixels: the gaps between the flame tongues above the
  /// ring are transparent too, and including them drags the apparent centre
  /// ~3px left and inflates the height by half.
  ///
  /// The hole is an oval sitting LOW in the frame (the flames lick up above
  /// it), so anything that wants the ring to encircle a subject must align to
  /// [holeCenterYFraction], not to the frame's centre.
  static const holeWidthFraction = 0.417;
  static const holeHeightFraction = 0.458;
  static const holeCenterXFraction = 0.490;
  static const holeCenterYFraction = 0.630;

  /// Frame side length whose hole is [holeWidth] across.
  static double sizeForHoleWidth(double holeWidth) =>
      holeWidth / holeWidthFraction;

  /// Where the hole's centre sits inside a frame of [size], measured from the
  /// frame's top-left. Position the frame so this lands on the subject's centre.
  static Offset holeCenter(double size) =>
      Offset(holeCenterXFraction * size, holeCenterYFraction * size);

  /// 0 at the lowest buff tier, 1 at [maxIntensityTier] and above.
  static double intensityFor(int tier) =>
      ((tier - 2) / (maxIntensityTier - 2)).clamp(0.0, 1.0);

  @override
  State<FireAura> createState() => _FireAuraState();
}

class _FireAuraState extends State<FireAura>
    with SingleTickerProviderStateMixin {
  // One controller drives BOTH rhythms: the flicker (frame index, cycling
  // `_flickerCycles` times per rotation) and the slow heat pulse (one breath
  // per rotation). Two controllers per row would double the ticker load on a
  // 20-row leaderboard for no visual gain.
  static const _rotation = Duration(milliseconds: 900);

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _rotation)
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Flicker loops per 900ms rotation. 1.7 at 2x reproduces the original ~90ms
  /// per frame; 3.5 at 8x+ is a frantic ~43ms.
  double get _flickerCycles => 1.7 + 1.8 * FireAura.intensityFor(widget.tier);

  @override
  Widget build(BuildContext context) {
    final t = FireAura.intensityFor(widget.tier);
    final disableAnimations = MediaQuery.of(context).disableAnimations;

    // Every ramp below is keyed off `t` so a 2x and an 11x are unmistakably
    // different flames rather than the same loop at the same brightness.
    final opacity = 0.72 + 0.26 * t; // 0.72 → 0.98
    final heat = 0.5 * t; // white-hot colour grade
    final pulse = 0.02 + 0.07 * t; // ±2% → ±9% breathing
    final bloom = 5.0 * t; // blur sigma of the glow underneath

    final image = Image.asset(
      FireAura._asset,
      width: widget.size * FireAura._frameCount,
      height: widget.size,
      fit: BoxFit.fitHeight,
      filterQuality: FilterQuality.none,
      // Older clients / a missing bundle simply render nothing (no crash).
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );

    Widget frameAt(int frame) => ClipRect(
      child: OverflowBox(
        maxWidth: double.infinity,
        alignment: Alignment.topLeft,
        child: Transform.translate(
          offset: Offset(-frame * widget.size, 0),
          child: image,
        ),
      ),
    );

    // Grade the flame toward white-hot. srcATop tints only where the sprite is
    // already opaque — a `plus`/`screen` blend would light up the transparent
    // frame box into a glowing square.
    Widget graded(Widget child) => heat <= 0.01
        ? child
        : ColorFiltered(
            colorFilter: ColorFilter.mode(
              Color.fromRGBO(255, 238, 170, heat),
              BlendMode.srcATop,
            ),
            child: child,
          );

    Widget composed(int frame) {
      final flame = graded(frameAt(frame));
      if (bloom < 0.6) return flame;
      // A blurred copy underneath is the bloom. Gated on tier so low tiers pay
      // nothing for a blur they wouldn't show anyway.
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: bloom, sigmaY: bloom),
              child: flame,
            ),
          ),
          flame,
        ],
      );
    }

    final animated = disableAnimations
        ? composed(2)
        : AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final v = _controller.value;
              final frame =
                  (v * _flickerCycles * FireAura._frameCount).floor() %
                  FireAura._frameCount;
              // Breathe once per rotation, scaled about the ring's own centre
              // so the pulse never walks the flame off the avatar.
              final scale = 1 + pulse * math.sin(v * 2 * math.pi);
              return Transform.scale(
                scale: scale,
                alignment: const Alignment(
                  FireAura.holeCenterXFraction * 2 - 1,
                  FireAura.holeCenterYFraction * 2 - 1,
                ),
                child: composed(frame),
              );
            },
          );

    final flame = SizedBox(
      width: widget.size,
      height: widget.size,
      child: animated,
    );

    return IgnorePointer(child: Opacity(opacity: opacity, child: flame));
  }
}
