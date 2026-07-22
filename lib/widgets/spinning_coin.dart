import 'package:flutter/material.dart';

import '../styles.dart';
import 'spinning_face.dart';

class SpinningCoin extends StatelessWidget {
  final double size;

  const SpinningCoin({super.key, this.size = 20});

  @override
  Widget build(BuildContext context) {
    return SpinningFace(child: _CoinFace(size: size));
  }
}

class _CoinFace extends StatelessWidget {
  final double size;

  const _CoinFace({required this.size});

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
