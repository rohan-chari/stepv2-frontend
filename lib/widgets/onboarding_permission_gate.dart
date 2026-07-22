import 'package:flutter/material.dart';

import '../styles.dart';
import 'onboarding_scene.dart';
import 'pill_button.dart';

/// Full-screen onboarding step that asks the user to grant a permission
/// (health, notifications). Shared by the onboarding flow's steps.
/// Rendered in the title screen's language via [OnboardingScene]: headline in
/// the night sky, permission icon hovering as the emblem, capybara on the
/// ground, and the copy + CONTINUE in the parchment dock.
class OnboardingPermissionGate extends StatelessWidget {
  const OnboardingPermissionGate({
    super.key,
    required this.label,
    required this.headline,
    required this.body,
    required this.icon,
    required this.onContinue,
    this.error,
    this.isLoading = false,
    this.retryLabel,
  });

  final String label;
  final String headline;
  final String body;
  final IconData icon;
  final VoidCallback onContinue;
  final String? error;
  final bool isLoading;

  /// When an [error] is showing (e.g. permission was denied), the primary
  /// button uses this label instead of "CONTINUE" so the user understands
  /// tapping it retries the request rather than moving on.
  final String? retryLabel;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return OnboardingScene(
      headline: headline,
      emblem: _PermissionEmblem(icon: icon),
      dockLabel: label,
      dockBody: body,
      error: error,
      actions: [
        if (isLoading)
          SizedBox(
            height: 52,
            child: Center(
              child: CircularProgressIndicator(
                color: colors.accent,
                strokeWidth: 3,
              ),
            ),
          )
        else
          SizedBox(
            width: double.infinity,
            height: 54,
            child: PillButton(
              label: (error != null && retryLabel != null)
                  ? retryLabel!
                  : 'CONTINUE',
              variant: PillButtonVariant.secondary,
              fullWidth: true,
              padding: EdgeInsets.zero,
              icon: icon,
              onPressed: onContinue,
            ),
          ),
      ],
    );
  }
}

/// The permission icon floating in the night sky — a soft moonlit ring, sized
/// to read as scenery rather than chrome.
class _PermissionEmblem extends StatelessWidget {
  const _PermissionEmblem({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      width: 108,
      height: 108,
      decoration: BoxDecoration(
        color: colors.textLight.withValues(alpha: 0.12),
        shape: BoxShape.circle,
        border: Border.all(
          color: colors.textLight.withValues(alpha: 0.30),
          width: 3,
        ),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 52, color: colors.textLight),
    );
  }
}
