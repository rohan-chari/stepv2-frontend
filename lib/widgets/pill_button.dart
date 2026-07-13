import 'package:flutter/material.dart';
import '../styles.dart';

enum PillButtonVariant { primary, secondary, accent }

class PillButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final PillButtonVariant variant;
  final double fontSize;
  final EdgeInsets padding;
  final bool fullWidth;
  final IconData? icon;
  final Widget? trailing;

  const PillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = PillButtonVariant.primary,
    this.fontSize = 15,
    this.padding = const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
    this.fullWidth = false,
    this.icon,
    this.trailing,
  });

  @override
  State<PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<PillButton> {
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
    final (face, dark, shadow) = _colors();
    final disabledFace = face.withValues(alpha: 0.45);
    final disabledDark = dark.withValues(alpha: 0.45);

    final activeFace = _enabled ? face : disabledFace;
    final activeDark = _enabled ? dark : disabledDark;

    final bool darkText = widget.variant == PillButtonVariant.secondary;
    final textColor = _enabled
        ? (darkText ? AppColors.textDark : Colors.white)
        : (darkText
              ? AppColors.textDark.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.7));

    final child = GestureDetector(
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
        transform: Matrix4.translationValues(0, _pressed ? 4 : 0, 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: activeFace,
          border: Border.all(color: activeDark, width: 2),
          // Straight-down hard shadow: the press animation drops the button
          // 4px onto it, so it reads as a physical underside — no diagonal
          // smear on textured backgrounds.
          boxShadow: _pressed
              ? []
              : [
                  BoxShadow(
                    color: shadow.withValues(alpha: _enabled ? 0.55 : 0.25),
                    offset: const Offset(0, 4),
                    blurRadius: 0,
                  ),
                ],
        ),
        padding: widget.padding,
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (widget.icon != null) ...[
              Icon(widget.icon, size: widget.fontSize + 2, color: textColor),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                widget.label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PixelText.pill(size: widget.fontSize, color: textColor),
              ),
            ),
            if (widget.trailing != null) ...[
              const SizedBox(width: 8),
              widget.trailing!,
            ],
          ],
        ),
      ),
    );

    if (widget.fullWidth) {
      return SizedBox(width: double.infinity, child: child);
    }
    return child;
  }
}
