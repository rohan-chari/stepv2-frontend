import 'package:flutter/material.dart';
import '../styles.dart';

class GameButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
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

  static const _gold = Color(0xFFF5C842);
  static const _goldMid = Color(0xFFEBB030);
  static const _goldDark = Color(0xFFD4991E);
  static const _goldBorder = Color(0xFFB8860B);
  static const _goldShadow = Color(0xFF8B6508);
  static const _goldText = Color(0xFF7A5A00);
  static const _goldGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [_gold, _goldMid, _goldDark],
  );

  static const _disabledGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFBBBBBB), Color(0xFFAAAAAA), Color(0xFF999999)],
  );
  static const _disabledBorder = Color(0xFF888888);
  static const _disabledShadow = Color(0xFF666666);
  static const _disabledText = Color(0xFF666666);

  bool get _enabled => widget.onPressed != null;

  @override
  Widget build(BuildContext context) {
    final gradient = _enabled ? _goldGradient : _disabledGradient;
    final borderColor = _enabled ? _goldBorder : _disabledBorder;
    final shadowColor = _enabled ? _goldShadow : _disabledShadow;
    final textColor = _enabled ? _goldText : _disabledText;

    return GestureDetector(
      onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: _enabled
          ? (_) {
              setState(() => _pressed = false);
              widget.onPressed!();
            }
          : null,
      onTapCancel: _enabled ? () => setState(() => _pressed = false) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 60),
        transform: Matrix4.translationValues(0, _pressed ? 6 : 0, 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: borderColor,
          boxShadow: _pressed
              ? []
              : [
                  BoxShadow(
                    color: shadowColor,
                    offset: const Offset(0, 6),
                    blurRadius: 0,
                  ),
                ],
        ),
        child: Container(
          padding: widget.padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: gradient,
            border: Border.all(
              color: borderColor,
              width: 2.5,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            widget.label,
            textAlign: TextAlign.center,
            style: PixelText.button(
              size: widget.fontSize,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }
}
