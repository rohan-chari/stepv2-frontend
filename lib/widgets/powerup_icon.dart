import 'package:flutter/material.dart';

import '../config/animals.dart';
import '../styles.dart';
import 'spinning_face.dart';

class PowerupIcon extends StatelessWidget {
  final String type;
  final double size;
  final bool spinning;
  final Duration spinDuration;

  const PowerupIcon({
    super.key,
    required this.type,
    this.size = 22,
    this.spinning = false,
    this.spinDuration = const Duration(milliseconds: 2800),
  });

  static const _assetNames = {
    'LEG_CRAMP': 'leg_cramp',
    'RED_CARD': 'red_card',
    'SHORTCUT': 'shortcut',
    'COMPRESSION_SOCKS': 'compression_socks',
    'PROTEIN_SHAKE': 'protein_shake',
    'RUNNERS_HIGH': 'runners_high',
    'SECOND_WIND': 'second_wind',
    'STEALTH_MODE': 'stealth_mode',
    'WRONG_TURN': 'wrong_turn',
    'FANNY_PACK': 'fanny_pack',
    'TRAIL_MIX': 'trail_mix',
    'DETOUR_SIGN': 'detour_sign',
    'LUCKY_HORSESHOE': 'lucky_horseshoe',
    'CAMPFIRE_REST': 'campfire_rest',
    'TRAIL_MAGNET': 'trail_magnet',
    'POCKET_WATCH': 'pocket_watch',
    'TRAIL_MINE': 'trail_mine',
    'PINECONE_TOSS': 'pinecone_toss',
    'SNEAKY_SWAP': 'sneaky_swap',
    'MIRROR': 'mirror',
    'CLEANSE': 'cleanse',
    'IMPOSTER': 'imposter',
    'RAINSTORM': 'rainstorm',
    'SIGNAL_JAMMER': 'signal_jammer',
    'LEECH': 'leech',
    'DEFENSE_SCAN': 'defense_scan',
    // §7/§8 store-only additions. Both ship 128x128 art plus a tightly-cropped
    // `_thumb` variant, so thumb-first rendering doesn't repeat the
    // leech/defense_scan gap.
    'HITCHHIKE': 'hitchhike',
    'QUICK_RINSE': 'quick_rinse',
    'QUICKSAND': 'quicksand',
    // §7 powerups5 store-only additions — generated via the Codex imagegen
    // pipeline (CLAUDE.md), same side-profile pixel-art style as the wave above.
    'UPRISING': 'uprising',
    'GHOST_PEPPER': 'ghost_pepper',
    'COIN_FLIP': 'coin_flip',
    'MYSTERY_POTION': 'mystery_potion',
    'DECOY': 'decoy',
    'POWER_OUTAGE': 'power_outage',
    'UMBRELLA': 'umbrella',
    'RALLY_FLAG': 'rally_flag',
    'DRILL_SERGEANT': 'drill_sergeant',
    'PIGGY_BANK': 'piggy_bank',
    'BOUNTY': 'bounty',
  };

  /// Interceptor keys that are NOT powerups and ship no art of their own, but
  /// which the attack-outcome modal and the race feed must still draw. They
  /// render a glyph from the shared fallback tile rather than a bespoke sprite
  /// (CLAUDE.md: never hand-draw artwork). Deliberately kept out of
  /// [_assetNames] so [knownTypeCount] keeps counting real powerup art.
  static const _glyphFallbacks = {
    // Turtle character's passive block — arrives as `blockedBy: "SHELL"`.
    'SHELL': Icons.shield_rounded,
  };

  static int get knownTypeCount => _assetNames.length;

  /// Full asset path for a powerup type, or null when unknown. Lets shop
  /// tiles render the art through AccessoryThumbnail (thumb-first, fills
  /// the tile) instead of at this widget's fixed icon size.
  static String? assetPathFor(String type) {
    final name = _assetNames[type.toUpperCase()];
    return name == null ? null : 'assets/images/powerups/$name.png';
  }

  @override
  Widget build(BuildContext context) {
    final key = type.toUpperCase();
    final assetName = _assetNames[key];
    final glyph = _glyphFallbacks[key];
    // SHELL has no bespoke powerup art (CLAUDE.md: never hand-draw artwork) —
    // it's the Turtle character's passive block, so use the same walk-sheet
    // art the character itself renders with, cropped to a static frame,
    // instead of a generic system glyph.
    if (key == 'SHELL') {
      final icon = SizedBox.square(
        dimension: size,
        child: _TurtleShellIcon(size: size),
      );
      if (!spinning) return icon;
      return SizedBox.square(
        dimension: size,
        child: SpinningFace(duration: spinDuration, child: icon),
      );
    }
    final icon = SizedBox.square(
      dimension: size,
      child: assetName == null
          ? _PowerupFallbackIcon(size: size, glyph: glyph)
          : Image.asset(
              'assets/images/powerups/$assetName.png',
              width: size,
              height: size,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.none,
              errorBuilder: (context, error, stackTrace) =>
                  _PowerupFallbackIcon(size: size, glyph: glyph),
            ),
    );

    if (!spinning) return icon;

    return SizedBox.square(
      dimension: size,
      child: SpinningFace(duration: spinDuration, child: icon),
    );
  }
}

/// A static frame-0 crop of the Turtle character's walk sheet, shown for a
/// Shell block instead of a generic glyph. Same crop technique as
/// `CapybaraSpriteWithAccessories` in home_course_track.dart (ClipRect +
/// OverflowBox isolates one frame from the sheet; frame 0 needs no
/// Transform.translate since it's already at the sheet's left edge), without
/// the accessory compositing that widget also does — a block icon needs only
/// the bare character.
class _TurtleShellIcon extends StatelessWidget {
  const _TurtleShellIcon({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final sprite = animalSpriteFor('turtle');
    // Real powerup art (compression_socks.png, mirror.png, ...) renders as a
    // bare transparent-bg image with no card, sized to fill the icon box —
    // match that treatment rather than the parchment-tile fallback so Shell
    // reads like the other real powerup icons in the same modal.
    return ClipRect(
      child: OverflowBox(
        maxWidth: double.infinity,
        alignment: Alignment.topLeft,
        child: Image.asset(
          sprite.asset,
          width: size * sprite.frameCount,
          height: size,
          filterQuality: FilterQuality.none,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) =>
              SizedBox.square(
                dimension: size,
                child: Icon(Icons.shield_rounded, size: size * 0.62),
              ),
        ),
      ),
    );
  }
}

class _PowerupFallbackIcon extends StatelessWidget {
  const _PowerupFallbackIcon({required this.size, this.glyph});

  final double size;

  /// Overrides the generic bolt for keys that have a meaningful glyph but no
  /// art (e.g. the Turtle's SHELL block → a shield).
  final IconData? glyph;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.of(context).parchmentDark,
        borderRadius: BorderRadius.circular(size * 0.18),
        border: Border.all(
          color: AppColors.of(context).parchmentBorder,
          width: 1.5,
        ),
      ),
      child: Icon(
        glyph ?? Icons.bolt_rounded,
        size: size * 0.62,
        color: glyph == null
            ? AppColors.of(context).coinDark
            : AppColors.of(context).feedShield,
      ),
    );
  }
}
