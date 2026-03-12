import 'package:flutter/material.dart';
import '../styles.dart';

class GameButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;
  final double fontSize;
  final EdgeInsets padding;

  const GameButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.fontSize = 26,
    this.padding = const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
  });

  @override
  State<GameButton> createState() => _GameButtonState();
}

class _GameButtonState extends State<GameButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onPressed();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 60),
        transform: Matrix4.translationValues(0, _pressed ? 6 : 0, 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: AppColors.goldBorder,
          boxShadow: _pressed
              ? []
              : [
                  const BoxShadow(
                    color: AppColors.goldShadow,
                    offset: Offset(0, 6),
                    blurRadius: 0,
                  ),
                ],
        ),
        child: Container(
          padding: widget.padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: AppColors.goldGradient,
            border: Border.all(
              color: AppColors.goldBorder,
              width: 2.5,
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: widget.fontSize,
              fontWeight: FontWeight.w900,
              color: AppColors.goldText,
              letterSpacing: 4,
              shadows: [
                Shadow(
                  color: AppColors.goldHighlight.withValues(alpha: 0.6),
                  offset: const Offset(0, 1),
                  blurRadius: 0,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
