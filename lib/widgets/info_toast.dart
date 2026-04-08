import 'package:flutter/material.dart';

import '../styles.dart';
import 'game_toast.dart';

/// Shows a floating game-styled info toast that slides down from the top
/// and auto-dismisses after [duration].
void showInfoToast(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 3),
}) {
  showGameToast(
    context,
    message,
    duration: duration,
    shellKey: const Key('info-toast-shell'),
    badgeKey: const Key('info-toast-badge'),
    palette: const GameToastPalette(
      label: 'NOTICE',
      icon: Icons.notifications_rounded,
      face: AppColors.pillGreen,
      dark: AppColors.pillGreenDark,
      shadow: AppColors.pillGreenShadow,
      messageColor: AppColors.textDark,
    ),
  );
}
