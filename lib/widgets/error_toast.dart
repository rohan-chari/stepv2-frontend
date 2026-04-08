import 'package:flutter/material.dart';

import '../styles.dart';
import 'game_toast.dart';

/// Shows a game-styled error toast that slides down from the top
/// and auto-dismisses after [duration].
void showErrorToast(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 3),
}) {
  showGameToast(
    context,
    message,
    duration: duration,
    shellKey: const Key('error-toast-shell'),
    badgeKey: const Key('error-toast-badge'),
    palette: const GameToastPalette(
      label: 'ERROR',
      icon: Icons.priority_high_rounded,
      face: AppColors.pillTerra,
      dark: AppColors.pillTerraDark,
      shadow: AppColors.pillTerraShadow,
      messageColor: AppColors.textDark,
    ),
  );
}
