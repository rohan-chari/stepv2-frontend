import 'package:flutter/material.dart';

import '../styles.dart';

enum ModalActionVariant { secondary, primary }

/// Text action used in compact dialogs. Dialog actions intentionally split
/// into the app's two core accents instead of making every action inherit the
/// same Material primary color.
class ModalActionButton extends StatelessWidget {
  const ModalActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = ModalActionVariant.primary,
  });

  final String label;
  final VoidCallback? onPressed;
  final ModalActionVariant variant;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final color = variant == ModalActionVariant.secondary
        ? colors.pillGoldDark
        : colors.pillGreenDark;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(foregroundColor: color),
      child: Text(label),
    );
  }
}
