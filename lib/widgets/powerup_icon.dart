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
  };

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
        color: AppColors.parchmentDark,
        borderRadius: BorderRadius.circular(size * 0.18),
        border: Border.all(color: AppColors.parchmentBorder, width: 1.5),
      ),
      child: Icon(
        Icons.bolt_rounded,
        size: size * 0.62,
        color: AppColors.coinDark,
      ),
    );
  }
}
