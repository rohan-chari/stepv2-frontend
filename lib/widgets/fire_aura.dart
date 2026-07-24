import 'package:flutter/material.dart';

/// Animated fire aura FX that renders BEHIND a character avatar to signal a
/// high step multiplier on the race-detail leaderboard.
///
/// Driven by a Codex-generated sprite sheet (`assets/images/fx/fire_aura.png`,
/// a 576x96 horizontal sheet of six 96x96 flicker frames — same layout as the
/// capybara walk sheet). Intensity (size + opacity) scales per integer
/// multiplier tier. Honors [MediaQuery.disableAnimations]: when set, the flame
/// freezes on a single frame instead of cycling.
class FireAura extends StatefulWidget {
  const FireAura({super.key, required this.size, required this.tier});

  /// Side length of the (square) box the flame fills. Should be larger than the
  /// avatar it sits behind so the flame licks around the edges.
  final double size;

  /// Multiplier tier = floor(multiplier). Only meaningful for tiers >= 2 (the
  /// caller renders nothing at 1x). Higher tiers glow brighter.
  final int tier;

  static const _asset = 'assets/images/fx/fire_aura.png';
  static const _frameCount = 6;

  @override
  State<FireAura> createState() => _FireAuraState();
}

class _FireAuraState extends State<FireAura>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 540), // ~90ms/frame, 6 frames
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.of(context).disableAnimations;
    // Opacity ramps with tier but stays translucent so the avatar reads through
    // the flame. Clamped so tier 5+ doesn't wash out the row.
    final opacity = (0.55 + 0.09 * (widget.tier - 2)).clamp(0.5, 0.9);

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

    final flame = SizedBox(
      width: widget.size,
      height: widget.size,
      child: disableAnimations
          ? frameAt(2)
          : AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final frame =
                    (_controller.value * FireAura._frameCount).floor() %
                    FireAura._frameCount;
                return frameAt(frame);
              },
            ),
    );

    return IgnorePointer(child: Opacity(opacity: opacity, child: flame));
  }
}
