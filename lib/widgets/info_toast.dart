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
    palette: GameToastPalette(
      label: 'NOTICE',
      icon: Icons.notifications_rounded,
      face: AppColors.of(context).pillGreen,
      dark: AppColors.of(context).pillGreenDark,
      shadow: AppColors.of(context).pillGreenShadow,
      messageColor: AppColors.of(context).textDark,
    ),
  );
}
