import 'package:flutter/material.dart';

import '../styles.dart';
import 'spinning_coin.dart';

class CoinBalanceBadge extends StatefulWidget {
  final int coins;
  final double coinSize;
  final VoidCallback? onTap;

  const CoinBalanceBadge({
    super.key,
    required this.coins,
    this.coinSize = 18,
    this.onTap,
  });

  @override
  State<CoinBalanceBadge> createState() => _CoinBalanceBadgeState();
}

class _CoinBalanceBadgeState extends State<CoinBalanceBadge> {
  static const _textShadows = [
    Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isTappable = widget.onTap != null;

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SpinningCoin(size: widget.coinSize),
        const SizedBox(width: 3),
        Text(
          '${widget.coins}',
          style: PixelText.number(
            size: 16,
            color: AppColors.coinDark,
          ).copyWith(shadows: _textShadows),
        ),
        if (isTappable) ...[
          const SizedBox(width: 2),
          Icon(
            Icons.chevron_right_rounded,
            size: widget.coinSize,
            color: AppColors.coinDark,
            shadows: _textShadows,
          ),
        ],
      ],
    );

    if (!isTappable) return content;

    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: content,
      ),
    );
  }
}
