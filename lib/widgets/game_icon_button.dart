import 'package:flutter/material.dart';

/// A small icon button with the same 3D press effect as GameButton.
class GameIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final double size;

  const GameIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = 36,
  });

  @override
  State<GameIconButton> createState() => _GameIconButtonState();
}

class _GameIconButtonState extends State<GameIconButton> {
  bool _pressed = false;

  static const _gold = Color(0xFFF5C842);
  static const _goldMid = Color(0xFFEBB030);
  static const _goldDark = Color(0xFFD4991E);
  static const _goldBorder = Color(0xFFB8860B);
  static const _goldShadow = Color(0xFF8B6508);
  static const _goldIcon = Color(0xFF7A5A00);
  static const _goldIconDisabled = Color(0xFFBFA050);
  static const _goldGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [_gold, _goldMid, _goldDark],
  );

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;

    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: enabled
          ? (_) {
              setState(() => _pressed = false);
              widget.onPressed!();
            }
          : null,
      onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 60),
        transform: Matrix4.translationValues(0, _pressed ? 3 : 0, 0),
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: _goldBorder,
          boxShadow: _pressed
              ? []
              : const [
                  BoxShadow(
                    color: _goldShadow,
                    offset: Offset(0, 3),
                    blurRadius: 0,
                  ),
                ],
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            gradient: _goldGradient,
            border: Border.all(color: _goldBorder, width: 2),
          ),
          child: Icon(
            widget.icon,
            size: widget.size * 0.5,
            color: enabled ? _goldIcon : _goldIconDisabled,
          ),
        ),
      ),
    );
  }
}
