import 'package:flutter/material.dart';

import '../styles.dart';
import 'game_container.dart';
import 'pill_button.dart';

/// The relocated notification ask (spec §5.4).
///
/// It no longer sits in the onboarding critical path; it fires the first time
/// the user opens a mystery box, with a third-session backstop for anyone who
/// never opens one.
///
/// **The copy is a hard constraint, not a style choice.** There is no
/// box-ready push and no powerup-earned push in the product — only race
/// pushes (`RACE_STARTED`, `PLACEMENT_CHANGED`, `RACE_ENDING_SOON`,
/// `POWERUP_USED`, `RACE_COMPLETED`, and the `TEAM_*` family). Promising
/// anything box- or powerup-shaped here would be a lie the app cannot keep, so
/// the framing stays vague and race-oriented. A test asserts the rendered copy
/// contains neither word.
class NotificationAskDialog extends StatelessWidget {
  const NotificationAskDialog({
    super.key,
    required this.onEnable,
    required this.onNotNow,
  });

  final VoidCallback onEnable;
  final VoidCallback onNotNow;

  /// Shows the ask over [context]. Resolves to true when the user tapped
  /// ENABLE, false for NOT NOW or a barrier dismissal.
  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.62),
      builder: (dialogContext) => NotificationAskDialog(
        onEnable: () => Navigator.of(dialogContext).pop(true),
        onNotNow: () => Navigator.of(dialogContext).pop(false),
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      child: GameContainer(
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
        frameColor: colors.accent,
        surfaceColor: colors.parchmentLight,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // A bell would say "alerts". A finish flag says "races", which is
            // the only thing this permission actually buys the user.
            Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                color: colors.accent.withValues(alpha: 0.14),
                shape: BoxShape.circle,
                border: Border.all(
                  color: colors.accent.withValues(alpha: 0.34),
                  width: 3,
                ),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.sports_score_rounded,
                size: 36,
                color: colors.accent,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Stay in the race',
              textAlign: TextAlign.center,
              style: PixelText.title(size: 22, color: colors.textDark),
            ),
            const SizedBox(height: 8),
            Text(
              'Get notified about what’s happening in your races.',
              textAlign: TextAlign.center,
              style: PixelText.body(size: 14, color: colors.textMid),
            ),
            const SizedBox(height: 20),
            PillButton(
              label: 'ENABLE',
              variant: PillButtonVariant.primary,
              fullWidth: true,
              onPressed: onEnable,
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: onNotNow,
              child: Text(
                'NOT NOW',
                style: PixelText.title(size: 13, color: colors.textMid),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
