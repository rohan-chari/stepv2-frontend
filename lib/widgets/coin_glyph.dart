import 'package:flutter/material.dart';

import '../styles.dart';

/// The app's coin, as a static glyph.
///
/// Material's `Icons.monetization_on_rounded` is a **dollar sign** — real
/// money, which is exactly what a soft-currency coin must not look like. The
/// coin users already recognise is the paw coin behind the header balance
/// (`SpinningCoin` → `assets/images/coin.png`), so every price in the app uses
/// the same artwork.
///
/// Deliberately **not** [SpinningCoin]: a shop grid can hold twenty prices at
/// once, and twenty spinning coins is animation cost with no meaning. Here the
/// coin is a unit label, not a hero element — the header badge stays the one
/// thing that spins.
///
/// Falls back to the same drawn paw-coin as [SpinningCoin] if the asset is
/// missing, so an older bundle can never render an empty box where a price was.
class CoinGlyph extends StatelessWidget {
  const CoinGlyph({super.key, this.size = 14});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        'assets/images/coin.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        errorBuilder: (context, error, stackTrace) => _CoinFallback(size: size),
      ),
    );
  }
}

class _CoinFallback extends StatelessWidget {
  const _CoinFallback({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.of(context).coinLight,
        border: Border.all(color: AppColors.of(context).coinEdge, width: 1.5),
      ),
      child: Center(
        child: Icon(
          Icons.pets_rounded,
          size: size * 0.54,
          color: AppColors.of(context).coinEdge,
        ),
      ),
    );
  }
}
