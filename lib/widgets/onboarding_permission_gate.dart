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
    this.onOpenSettings,
    this.onEscape,
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

  /// Non-null once retrying has stopped being useful (the OS has refused
  /// twice). The primary CTA then launches the platform's health settings
  /// instead of firing another prompt that will never appear.
  ///
  /// The widget stays dumb: it renders what it is given and never decides when
  /// the ladder advances. That call belongs to the host.
  final VoidCallback? onOpenSettings;

  /// Non-null once the user is allowed out of the gate into the degraded
  /// "steps not connected" state. Absent (the default) the gate looks and
  /// behaves exactly as it does today — which is what keeps the notifications
  /// gate on v1/v2 visually untouched.
  final VoidCallback? onEscape;

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
              label: onOpenSettings != null
                  ? 'OPEN HEALTH CONNECT SETTINGS'
                  : (error != null && retryLabel != null)
                  ? retryLabel!
                  : 'CONTINUE',
              variant: PillButtonVariant.secondary,
              fullWidth: true,
              padding: EdgeInsets.zero,
              fontSize: onOpenSettings != null ? 13 : 15,
              icon: onOpenSettings != null ? Icons.settings_rounded : icon,
              onPressed: onOpenSettings ?? onContinue,
            ),
          ),
        // The way out. A blocking step with no escape is the exact failure mode
        // the degraded state exists to fix, so once the OS has stopped
        // cooperating the user gets a door — quiet, secondary, never the
        // headline offer.
        if (onEscape != null && !isLoading) ...[
          const SizedBox(height: 2),
          TextButton(
            onPressed: onEscape,
            child: Text(
              'Continue without steps',
              style: PixelText.body(
                size: 14,
                color: colors.textMid,
              ).copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        ],
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
      decoration: onboardingSkyRing(context, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Icon(icon, size: 52, color: colors.textLight),
    );
  }
}
