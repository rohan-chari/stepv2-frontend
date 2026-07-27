import 'package:flutter/material.dart';

import '../styles.dart';

/// The home hero's pace line, mounted on a wooden trail-sign plank.
///
/// It used to sit directly on the scrolling ground strip with only a drop
/// shadow between it and the brick/dirt texture, so the line read as floating
/// debris rather than as part of the scene. Standing it on signage gives the
/// text an opaque surface of its own and makes it read as a trail marker the
/// capybara is walking past (batch 2026-07-27 item 18).
///
/// The plank is generated pixel art (`assets/images/trail_sign_plank.png`,
/// produced through the Codex imagegen pipeline — never hand-drawn), sign top
/// only, no post.
class HeroPaceSign extends StatelessWidget {
  const HeroPaceSign({super.key, required this.text});

  final String text;

  /// The plank's mid-tone wood, sampled from the asset.
  ///
  /// Only used to prove the ink's contrast in tests — the widget itself never
  /// paints it, because the wood comes from the PNG.
  static const plankWood = Color(0xFFCA7F41);

  /// The pace line's colour.
  ///
  /// Deliberately a fixed colour rather than an [AppColors] token. The plank is
  /// a fixed-colour PNG that looks identical in both palettes, so a token that
  /// flips for night mode would go invisible on the wood — the same night-flip
  /// trap that made `roofMid`-as-text unreadable (item 11). This is the carved
  /// near-black of the house outline style and clears 4.5:1 on [plankWood].
  static const inkOnWood = Color(0xFF1A0E04);

  /// The asset's own aspect ratio, so the plank never distorts.
  static const _plankAspect = 449 / 93;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: _plankAspect,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/trail_sign_plank.png',
            key: const Key('hero-pace-sign-plank'),
            fit: BoxFit.fill,
            // Chunky pixel art: never let the sampler soften the edges.
            filterQuality: FilterQuality.none,
            // A missing asset must not take the whole hero down with it.
            errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
          ),
          // The knots and nail pegs live in the outer ~18% of the board, so the
          // text is inset past them onto the clean centre face.
          LayoutBuilder(
            builder: (context, constraints) {
              final inset = constraints.maxWidth * 0.16;
              return Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: inset,
                  vertical: constraints.maxHeight * 0.16,
                ),
                child: Center(
                  // Shrink rather than ellipsize — the same defect class as
                  // item 4's PillButton truncation. A clipped pace line is a
                  // silent failure; a slightly smaller one is not.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox(
                      width: constraints.maxWidth - inset * 2,
                      // No maxLines and no ellipsis on purpose: the line wraps
                      // freely at this width, and the FittedBox above scales
                      // the whole block down until it fits the board. Capping
                      // the lines would hand truncation back to the Text.
                      child: Text(
                        text,
                        key: const Key('hero-pace-sign-text'),
                        textAlign: TextAlign.center,
                        style: PixelText.body(size: 12, color: inkOnWood),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
