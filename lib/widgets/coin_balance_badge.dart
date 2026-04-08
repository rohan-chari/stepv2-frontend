import 'package:flutter/material.dart';

import '../styles.dart';
import 'spinning_coin.dart';

class CoinBalanceBadge extends StatelessWidget {
  final int coins;
  final int heldCoins;
  final double coinSize;

  const CoinBalanceBadge({
    super.key,
    required this.coins,
    this.heldCoins = 0,
    this.coinSize = 18,
  });

  static const _textShadows = [
    Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 4,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SpinningCoin(size: coinSize),
            const SizedBox(width: 3),
            Text(
              '$coins',
              style: PixelText.number(
                size: 16,
                color: AppColors.coinDark,
              ).copyWith(shadows: _textShadows),
            ),
          ],
        ),
        if (heldCoins > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.pillTerra, AppColors.pillTerraDark],
              ),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.pillGoldDark, width: 1.2),
              boxShadow: const [
                BoxShadow(
                  color: AppColors.pillTerraShadow,
                  offset: Offset(0, 2),
                  blurRadius: 0,
                ),
              ],
            ),
            child: Text(
              'HOLD $heldCoins',
              style: PixelText.title(size: 10, color: Colors.white),
            ),
          ),
      ],
    );
  }
}
