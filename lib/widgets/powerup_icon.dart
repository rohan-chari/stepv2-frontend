import 'package:flutter/material.dart';

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
    final assetName = _assetNames[type.toUpperCase()];
    final icon = SizedBox.square(
      dimension: size,
      child: assetName == null
          ? _PowerupFallbackIcon(size: size)
          : Image.asset(
              'assets/images/powerups/$assetName.png',
              width: size,
              height: size,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.none,
              errorBuilder: (context, error, stackTrace) =>
                  _PowerupFallbackIcon(size: size),
            ),
    );

    if (!spinning) return icon;

    return SizedBox.square(
      dimension: size,
      child: SpinningFace(duration: spinDuration, child: icon),
    );
  }
}

class _PowerupFallbackIcon extends StatelessWidget {
  const _PowerupFallbackIcon({required this.size});

  final double size;

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
        Icons.bolt_rounded,
        size: size * 0.62,
        color: AppColors.of(context).coinDark,
      ),
    );
  }
}
