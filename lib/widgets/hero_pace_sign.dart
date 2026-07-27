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

  /// A one-pixel warm highlight under each glyph, as if the line were routed
  /// into the board and catching light on its lower lip.
  ///
  /// Fixed colours for the same reason [inkOnWood] is: the plank art does not
  /// change between palettes, so nothing painted on it may either. Its job is
  /// legibility — the wood grain runs horizontally straight through the text,
  /// and the highlight separates the glyph edges from it in both modes.
  static const _carveHighlight = <Shadow>[
    Shadow(color: Color(0x80FFD9A6), offset: Offset(0, 1)),
  ];

  /// The asset's own aspect ratio, so the plank never distorts.
  static const plankAspect = 449 / 93;

  /// Board height for the home hero.
  ///
  /// The first version stood 40pt tall, which left a ~131×27pt text window —
  /// far too small for a two-sentence pace line, so the [FittedBox] below
  /// shrank the copy to roughly 7pt and it read as illegible scribble on the
  /// wood. The board is now sized from the copy instead of the other way
  /// round: big enough that the pace line reads at something close to its
  /// natural size, rather than the ~7pt the original 40pt board forced.
  ///
  /// The ceiling is the scene, not the copy. The board is planted in the dirt
  /// strip, so its top edge has to stay below the grass fringe at the top of
  /// that strip (`groundHeight` is 84 in home_tab, and the grass band is the
  /// top ~12 of it) — at 70 the board rose into the grass and clipped the
  /// mascot's feet. 62 leaves the fringe clear.
  static double heightFor({required bool compact}) => compact ? 56 : 62;

  /// Base size of the pace line. The board is sized around it, not the other
  /// way round — see [heightFor].
  static const textSize = 14.0;

  /// Fraction of the board's height given to the text window. The board's top
  /// and bottom edges are clean art, so this is deliberately tight.
  static const _verticalInsetFraction = 0.08;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: plankAspect,
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
          // The knots and nail pegs live in the outer ~15% of the board (the
          // left knot sits at ~8% and the right at ~88% of the width), so the
          // text is inset past them onto the clean centre face. The vertical
          // inset is deliberately tighter than the horizontal one: the board's
          // top and bottom edges are clean, and every point given back here is
          // a point of type size.
          LayoutBuilder(
            builder: (context, constraints) {
              final inset = constraints.maxWidth * 0.15;
              return Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: inset,
                  vertical: constraints.maxHeight * _verticalInsetFraction,
                ),
                child: Center(
                  key: const Key('hero-pace-sign-window'),
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
                        style: PixelText.body(size: textSize, color: inkOnWood)
                            .copyWith(shadows: _carveHighlight),
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
