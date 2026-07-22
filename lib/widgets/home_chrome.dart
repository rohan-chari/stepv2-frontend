import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../styles.dart';

abstract final class HomeText {
  static TextStyle display({
    double size = 34,
    Color color = AppColors.textDark,
  }) {
    return GoogleFonts.spaceGrotesk(
      fontSize: size,
      height: 1.0,
      fontWeight: FontWeight.w800,
      color: color,
      letterSpacing: 0,
    );
  }

  static TextStyle title({double size = 20, Color color = AppColors.textDark}) {
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
    Color color = AppColors.textDark,
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

  static TextStyle label({double size = 12, Color color = AppColors.textMid}) {
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
    this.backgroundColor,
    this.borderColor,
    this.radius = 8,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;
  final Color? borderColor;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.of(context).surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: borderColor ?? AppColors.of(context).lineSoft,
          width: 2,
        ),
        boxShadow: radius == 0
            ? null
            : [
                BoxShadow(
                  color: (borderColor ?? AppColors.of(context).lineSoft)
                      .withValues(alpha: 0.22),
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
    this.backgroundColor,
    this.borderColor,
    this.radius = 8,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;
  final Color? borderColor;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.of(context).surfaceMuted,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: borderColor ?? AppColors.of(context).lineSoft,
          width: 2,
        ),
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
    this.backgroundColor,
    this.foregroundColor,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    this.fullWidth = false,
    this.mainAxisAlignment = MainAxisAlignment.start,
  });

  final String label;
  final IconData? icon;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final EdgeInsetsGeometry padding;
  final bool fullWidth;
  final MainAxisAlignment mainAxisAlignment;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.of(context).surfaceMuted,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: (foregroundColor ?? AppColors.of(context).ink).withValues(
            alpha: 0.14,
          ),
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
              Icon(
                icon,
                size: 14,
                color: foregroundColor ?? AppColors.of(context).ink,
              ),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: HomeText.label(
                  size: 10,
                  color: foregroundColor ?? AppColors.of(context).ink,
                ),
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
    this.backgroundColor,
    this.foregroundColor,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? backgroundColor;
  final Color? foregroundColor;
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
              color: backgroundColor ?? AppColors.of(context).surfaceMuted,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: (foregroundColor ?? AppColors.of(context).ink)
                    .withValues(alpha: 0.14),
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
                    Icon(
                      icon,
                      size: 14,
                      color: foregroundColor ?? AppColors.of(context).ink,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: HomeText.label(
                        size: 10,
                        color: foregroundColor ?? AppColors.of(context).ink,
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
