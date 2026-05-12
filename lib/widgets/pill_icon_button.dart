import 'package:flutter/material.dart';
import 'pill_button.dart';
import '../styles.dart';

class PillIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final PillButtonVariant variant;

  const PillIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = 48,
    this.variant = PillButtonVariant.secondary,
  });

  @override
  State<PillIconButton> createState() => _PillIconButtonState();
}

class _PillIconButtonState extends State<PillIconButton> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null;

  (Color, Color, Color) _colors() {
    switch (widget.variant) {
      case PillButtonVariant.primary:
        return (
          AppColors.pillGreen,
          AppColors.pillGreenDark,
          AppColors.pillGreenShadow,
        );
      case PillButtonVariant.secondary:
        return (
          AppColors.pillGold,
          AppColors.pillGoldDark,
          AppColors.pillGoldShadow,
        );
      case PillButtonVariant.accent:
        return (
          AppColors.pillTerra,
          AppColors.pillTerraDark,
          AppColors.pillTerraShadow,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final (face, dark, _) = _colors();
    final bool darkIcon = widget.variant == PillButtonVariant.secondary;
    final iconColor = _enabled
        ? (darkIcon ? AppColors.textDark : Colors.white)
        : (darkIcon
              ? AppColors.textDark.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.5));

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
        transform: Matrix4.translationValues(0, _pressed ? 3 : 0, 0),
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: face,
          border: Border.all(color: dark, width: 2),
          boxShadow: _pressed
              ? []
              : [
                  BoxShadow(
                    color: dark.withValues(alpha: 0.24),
                    offset: const Offset(3, 3),
                    blurRadius: 0,
                  ),
                ],
        ),
        child: Icon(widget.icon, size: widget.size * 0.5, color: iconColor),
      ),
    );
  }
}
