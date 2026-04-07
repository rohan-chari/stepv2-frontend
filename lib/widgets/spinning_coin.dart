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
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.coinLight, AppColors.coinMid, AppColors.coinDark],
        ),
        border: Border.all(color: AppColors.coinEdge, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.coinMid.withValues(alpha: 0.4),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Center(
        child: Text(
          '\$',
          style: TextStyle(
            fontSize: size * 0.5,
            fontWeight: FontWeight.w900,
            color: AppColors.coinEdge,
            height: 1,
          ),
        ),
      ),
    );
  }
}
