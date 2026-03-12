import 'package:flutter/material.dart';
import '../models/step_data.dart';
import '../styles.dart';
import 'game_icon_button.dart';
import 'trail_sign.dart';

class StepCountCard extends StatelessWidget {
  final StepData? stepData;
  final bool isLoading;
  final String? error;
  final String? hint;
  final int? stepGoal;
  final VoidCallback? onRefresh;
  final VoidCallback? onSettings;

  const StepCountCard({
    super.key,
    this.stepData,
    this.isLoading = false,
    this.error,
    this.hint,
    this.stepGoal,
    this.onRefresh,
    this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return TrailSign(
      width: double.infinity,
      showTopRightPin: onRefresh == null && onSettings == null,
      child: Stack(
        children: [
          // Centered content
          SizedBox(
            width: double.infinity,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "TODAY'S STEPS",
                  style: PixelText.title(size: 18, color: AppColors.textMid),
                ),
                const SizedBox(height: 16),
                if (isLoading)
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      color: AppColors.accent,
                      strokeWidth: 3,
                    ),
                  )
                else if (error != null)
                  Text(
                    error!,
                    style: PixelText.body(size: 13, color: AppColors.error),
                    textAlign: TextAlign.center,
                  )
                else ...[
                  Text(
                    '${stepData?.steps ?? 0}',
                    style: PixelText.number(size: 42, color: AppColors.textAccent),
                    textAlign: TextAlign.center,
                  ),
                  if (stepGoal != null)
                    Text(
                      '/ $stepGoal',
                      style: PixelText.body(size: 16, color: AppColors.textMid),
                      textAlign: TextAlign.center,
                    ),
                ],
                if (hint != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    hint!,
                    style: PixelText.body(
                      size: 11,
                      color: AppColors.textMid.withValues(alpha: 0.6),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),

          // Refresh + settings buttons in top-right corner
          if (onRefresh != null || onSettings != null)
            Positioned(
              top: 0,
              right: 0,
              child: Column(
                children: [
                  if (onRefresh != null)
                    GameIconButton(
                      icon: Icons.refresh,
                      onPressed: isLoading ? null : onRefresh,
                    ),
                  if (onRefresh != null && onSettings != null)
                    const SizedBox(height: 8),
                  if (onSettings != null)
                    GameIconButton(
                      icon: Icons.settings,
                      onPressed: onSettings,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
