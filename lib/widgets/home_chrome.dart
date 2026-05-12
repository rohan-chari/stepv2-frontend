import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class HomeColors {
  static const ink = Color(0xFF213128);
  static const inkSoft = Color(0xFF345345);
  static const surface = Color(0xFFFFFBF5);
  static const surfaceMuted = Color(0xFFF3EBDD);
  static const line = Color(0xFF213128);
  static const lineSoft = Color(0xFFD0C5B4);
  static const sage = Color(0xFF4F8A6A);
  static const sageDeep = Color(0xFF2E5D47);
  static const clay = Color(0xFFD47C52);
  static const gold = Color(0xFFECC86A);
  static const cream = Color(0xFFF8F2E7);
  static const muted = Color(0xFF66796F);
  static const success = Color(0xFF2F7A49);
}

abstract final class HomeText {
  static TextStyle display({double size = 34, Color color = HomeColors.ink}) {
    return GoogleFonts.spaceGrotesk(
      fontSize: size,
      height: 1.0,
      fontWeight: FontWeight.w800,
      color: color,
      letterSpacing: 0,
    );
  }

  static TextStyle title({double size = 20, Color color = HomeColors.ink}) {
    return GoogleFonts.spaceGrotesk(
      fontSize: size,
      height: 1.08,
      fontWeight: FontWeight.w800,
      color: color,
      letterSpacing: 0,
    );
  }

  static TextStyle body({
    double size = 14,
    Color color = HomeColors.ink,
    FontWeight weight = FontWeight.w600,
    double height = 1.35,
  }) {
    return GoogleFonts.dmSans(
      fontSize: size,
      height: height,
      fontWeight: weight,
      color: color,
    );
  }

  static TextStyle label({double size = 12, Color color = HomeColors.muted}) {
    return GoogleFonts.dmSans(
      fontSize: size,
      height: 1.0,
      fontWeight: FontWeight.w800,
      color: color,
      letterSpacing: 0,
    );
  }
}

class HomePanel extends StatelessWidget {
  const HomePanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(22, 20, 22, 20),
    this.backgroundColor = HomeColors.surface,
    this.borderColor = HomeColors.lineSoft,
    this.radius = 8,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color backgroundColor;
  final Color borderColor;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor, width: 2),
        boxShadow: radius == 0
            ? null
            : [
                BoxShadow(
                  color: borderColor.withValues(alpha: 0.22),
                  blurRadius: 0,
                  offset: const Offset(4, 4),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class HomeInsetPanel extends StatelessWidget {
  const HomeInsetPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.backgroundColor = HomeColors.surfaceMuted,
    this.borderColor = HomeColors.lineSoft,
    this.radius = 8,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color backgroundColor;
  final Color borderColor;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor, width: 2),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class HomePill extends StatelessWidget {
  const HomePill({
    super.key,
    required this.label,
    this.icon,
    this.backgroundColor = HomeColors.surfaceMuted,
    this.foregroundColor = HomeColors.ink,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    this.fullWidth = false,
    this.mainAxisAlignment = MainAxisAlignment.start,
  });

  final String label;
  final IconData? icon;
  final Color backgroundColor;
  final Color foregroundColor;
  final EdgeInsetsGeometry padding;
  final bool fullWidth;
  final MainAxisAlignment mainAxisAlignment;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: foregroundColor.withValues(alpha: 0.14),
          width: 2,
        ),
      ),
      child: Padding(
        padding: padding,
        child: Row(
          mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: mainAxisAlignment,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: foregroundColor),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: HomeText.label(size: 10, color: foregroundColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HomePillButton extends StatelessWidget {
  const HomePillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.backgroundColor = HomeColors.surfaceMuted,
    this.foregroundColor = HomeColors.ink,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color backgroundColor;
  final Color foregroundColor;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onPressed == null ? 0.55 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Ink(
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: foregroundColor.withValues(alpha: 0.14),
                width: 2,
              ),
            ),
            child: Padding(
              padding: padding,
              child: Row(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 14, color: foregroundColor),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: HomeText.label(size: 10, color: foregroundColor),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HomeStatChip extends StatelessWidget {
  const HomeStatChip({
    super.key,
    required this.label,
    required this.value,
    this.backgroundColor = HomeColors.surfaceMuted,
    this.labelColor = HomeColors.muted,
    this.valueColor = HomeColors.ink,
  });

  final String label;
  final String value;
  final Color backgroundColor;
  final Color labelColor;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: valueColor.withValues(alpha: 0.12), width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label.toUpperCase(), style: HomeText.label(color: labelColor)),
            const SizedBox(height: 4),
            Text(value, style: HomeText.title(size: 18, color: valueColor)),
          ],
        ),
      ),
    );
  }
}

class HomeButton extends StatelessWidget {
  const HomeButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isPrimary = true,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isPrimary;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final fill = isPrimary ? HomeColors.ink : HomeColors.surface;
    final border = isPrimary ? HomeColors.ink : HomeColors.line;
    final text = isPrimary ? Colors.white : HomeColors.ink;

    return Opacity(
      opacity: onPressed == null ? 0.55 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(10),
          child: Ink(
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: border, width: 2),
              boxShadow: [
                BoxShadow(
                  color: border.withValues(alpha: 0.18),
                  offset: const Offset(0, 4),
                  blurRadius: 0,
                ),
              ],
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 14 : 18,
                vertical: compact ? 10 : 14,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: compact ? 16 : 18, color: text),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: HomeText.body(
                        size: compact ? 12 : 13,
                        color: text,
                        weight: FontWeight.w800,
                        height: 1.0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
