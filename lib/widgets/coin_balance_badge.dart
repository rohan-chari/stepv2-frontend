import 'package:flutter/material.dart';

import '../styles.dart';
import 'spinning_coin.dart';

class CoinBalanceBadge extends StatefulWidget {
  final int coins;
  final double coinSize;
  final VoidCallback? onTap;

  /// When set, renders a small gold "+" button after the balance — the
  /// earn-more affordance (opens the invite-friends screen). Independent of
  /// [onTap], which makes the balance itself tappable.
  final VoidCallback? onAddTap;

  const CoinBalanceBadge({
    super.key,
    required this.coins,
    this.coinSize = 18,
    this.onTap,
    this.onAddTap,
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
            size: 19,
            color: AppColors.of(context).coinLight,
          ).copyWith(shadows: _textShadows),
        ),
        if (isTappable) ...[
          const SizedBox(width: 2),
          Icon(
            Icons.chevron_right_rounded,
            size: widget.coinSize,
            color: AppColors.of(context).coinLight,
            shadows: _textShadows,
          ),
        ],
        if (widget.onAddTap != null) ...[
          const SizedBox(width: 6),
          _AddCoinsButton(size: widget.coinSize + 4, onTap: widget.onAddTap),
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

/// Small circular gold "+" next to the coin balance — the "earn more coins"
/// entry point. Styled like the hero header's circular help button, in the
/// badge's coin-gold palette, with the standard press-scale effect.
class _AddCoinsButton extends StatefulWidget {
  final double size;
  final VoidCallback? onTap;

  const _AddCoinsButton({required this.size, this.onTap});

  @override
  State<_AddCoinsButton> createState() => _AddCoinsButtonState();
}

class _AddCoinsButtonState extends State<_AddCoinsButton> {
  static const _shadows = [
    Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final button = Container(
      decoration: BoxDecoration(
        color: AppColors.of(context).coinMid.withValues(alpha: 0.28),
        shape: BoxShape.circle,
        border: Border.all(
          color: AppColors.of(context).coinLight.withValues(alpha: 0.7),
          width: 1.5,
        ),
      ),
      padding: const EdgeInsets.all(2),
      child: Icon(
        Icons.add_rounded,
        size: widget.size - 4,
        color: AppColors.of(context).coinLight,
        shadows: _shadows,
      ),
    );

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
        child: button,
      ),
    );
  }
}
