import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/backend_config.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../services/health_service.dart';
import '../services/notification_service.dart';
import '../services/onboarding_state_service.dart';
import '../styles.dart';
import '../theme_controller.dart';
import '../tutorial/tutorial_screen.dart';
import '../widgets/arcade_page.dart';
import '../widgets/error_toast.dart';
import '../widgets/pill_button.dart';
import '../widgets/pixel_switch.dart';
import '../widgets/trail_sign.dart';
import 'admin_screen.dart';
import 'display_name_screen.dart';
import 'start_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.authService,
    this.notificationService,
    this.backendApiService,
    required this.onSettingsChanged,
  });

  final AuthService authService;
  final NotificationService? notificationService;
  final BackendApiService? backendApiService;
  final VoidCallback onSettingsChanged;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ArcadePageBackground(
        headerHeight: 86,
        child: SafeArea(
          child: Column(
            children: [
              SizedBox(
                height: 72,
                child: Row(
                  children: [
                    IconButton(
                      key: const Key('settings-back'),
                      tooltip: 'Back',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'SETTINGS',
                        textAlign: TextAlign.center,
                        style: PixelText.title(size: 20, color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              Expanded(
                child: _SettingsContent(
                  authService: authService,
                  notificationService: notificationService,
                  backendApiService: backendApiService,
                  onSettingsChanged: onSettingsChanged,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsContent extends StatefulWidget {
  final AuthService authService;
  final NotificationService? notificationService;
  final BackendApiService? backendApiService;
  final VoidCallback onSettingsChanged;

  const _SettingsContent({
    required this.authService,
    this.notificationService,
    this.backendApiService,
    required this.onSettingsChanged,
  });

  @override
  State<_SettingsContent> createState() => _SettingsContentState();
}

class _SettingsContentState extends State<_SettingsContent> {
  Future<void> _openUrl(String path) async {
    final uri = Uri.parse('${BackendConfig.baseUrl}$path');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: TrailSign(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'DELETE ACCOUNT?',
                style: PixelText.title(
                  size: 18,
                  color: AppColors.of(context).textDark,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                'This permanently deletes your account, step history, '
                'friends, and coins.',
                style: PixelText.body(
                  size: 14,
                  color: AppColors.of(context).textMid,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'Coins held in active races are forfeited to the race pot. '
                'This cannot be undone.',
                style: PixelText.body(
                  size: 13,
                  color: AppColors.of(context).textMid,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              PillButton(
                label: 'DELETE',
                variant: PillButtonVariant.accent,
                fullWidth: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                onPressed: () => Navigator.of(ctx).pop(true),
              ),
              const SizedBox(height: 10),
              PillButton(
                label: 'CANCEL',
                variant: PillButtonVariant.secondary,
                fullWidth: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                onPressed: () => Navigator.of(ctx).pop(false),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      await widget.notificationService?.unregisterDeviceToken(
        widget.authService.authToken,
      );
      await widget.authService.deleteAccount();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const StartScreen()),
        (route) => false,
      );
    } catch (error) {
      if (!mounted) return;
      showErrorToast(context, 'Failed to delete account: $error');
    }
  }

  Future<void> _signOut() async {
    await widget.notificationService?.unregisterDeviceToken(
      widget.authService.authToken,
    );
    await widget.authService.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const StartScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeController = AppThemeScope.maybeOf(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SettingsSection(
            sectionKey: const Key('settings-section-profile'),
            title: 'PROFILE & PRIVACY',
            icon: Icons.person_rounded,
            children: [
              PillButton(
                label: 'EDIT DISPLAY NAME',
                variant: PillButtonVariant.secondary,
                fontSize: 13,
                fullWidth: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) =>
                          DisplayNameScreen(authService: widget.authService),
                    ),
                  );
                  widget.onSettingsChanged();
                },
              ),
              // The "hide me from the global leaderboard" switch moved onto the
              // Leaderboard tab itself (batch 2026-07-27 item 1) — see
              // lib/widgets/leaderboard_visibility_toggle.dart.
              // Health has never had a re-entry point anywhere in the app —
              // notifications did, health didn't — so a user who denied or
              // later revoked step access had no way back in. This is it.
              // Mirrors _NotificationToggle: it renders nothing at all once
              // steps are connected.
              _ConnectHealthRow(authService: widget.authService),
            ],
          ),
          if (themeController != null) ...[
            const SizedBox(height: 24),
            _SettingsSection(
              sectionKey: const Key('settings-section-appearance'),
              title: 'APPEARANCE',
              icon: Icons.palette_rounded,
              children: [
                _AppearancePreferenceControl(controller: themeController),
              ],
            ),
          ],
          if (widget.notificationService != null) ...[
            const SizedBox(height: 24),
            _SettingsSection(
              sectionKey: const Key('settings-section-notifications'),
              title: 'NOTIFICATIONS',
              icon: Icons.notifications_rounded,
              children: [
                _NotificationToggle(
                  notificationService: widget.notificationService!,
                  authToken: widget.authService.authToken,
                ),
                if (widget.backendApiService != null)
                  _DailyRewardReminderToggle(
                    authService: widget.authService,
                    notificationService: widget.notificationService!,
                    backendApiService: widget.backendApiService!,
                  ),
              ],
            ),
          ],
          if (widget.authService.isAdmin) ...[
            const SizedBox(height: 24),
            _SettingsSection(
              sectionKey: const Key('settings-section-admin'),
              title: 'ADMIN',
              icon: Icons.admin_panel_settings_rounded,
              children: [
                PillButton(
                  label: 'ADMIN TOOLS',
                  variant: PillButtonVariant.secondary,
                  fontSize: 13,
                  fullWidth: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) =>
                            AdminScreen(authService: widget.authService),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          _SettingsSection(
            sectionKey: const Key('settings-section-help'),
            title: 'HELP & LEGAL',
            icon: Icons.help_rounded,
            children: [
              PillButton(
                label: 'VIEW TUTORIAL',
                variant: PillButtonVariant.secondary,
                fontSize: 13,
                fullWidth: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          TutorialScreen(authService: widget.authService),
                      fullscreenDialog: true,
                    ),
                  );
                },
              ),
              PillButton(
                label: 'SUPPORT',
                variant: PillButtonVariant.secondary,
                fontSize: 13,
                fullWidth: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                onPressed: () => _openUrl('/support.html'),
              ),
              PillButton(
                label: 'PRIVACY POLICY',
                variant: PillButtonVariant.secondary,
                fontSize: 13,
                fullWidth: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                onPressed: () => _openUrl('/privacy.html'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _SettingsSection(
            sectionKey: const Key('settings-section-account'),
            title: 'ACCOUNT',
            icon: Icons.lock_rounded,
            children: [
              PillButton(
                label: 'SIGN OUT',
                variant: PillButtonVariant.accent,
                fontSize: 13,
                fullWidth: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                onPressed: _signOut,
              ),
              PillButton(
                label: 'DELETE ACCOUNT',
                variant: PillButtonVariant.accent,
                fontSize: 13,
                fullWidth: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                onPressed: _confirmDeleteAccount,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.sectionKey,
    required this.title,
    required this.icon,
    required this.children,
  });

  final Key sectionKey;
  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Column(
      key: sectionKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: colors.textAccent),
            const SizedBox(width: 7),
            Text(
              title,
              style: PixelText.title(size: 12, color: colors.textAccent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(height: 1, color: colors.parchmentBorder),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (var index = 0; index < children.length; index++) ...[
          if (index > 0) const SizedBox(height: 10),
          children[index],
        ],
      ],
    );
  }
}

class _AppearancePreferenceControl extends StatelessWidget {
  const _AppearancePreferenceControl({required this.controller});

  final AppThemeController controller;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      key: const Key('appearance-preference-control'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.parchmentLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.parchmentBorder, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (final preference in AppThemePreference.values) ...[
                if (preference != AppThemePreference.automatic)
                  const SizedBox(width: 6),
                Expanded(
                  child: _AppearanceChoice(
                    preference: preference,
                    selected: controller.preference == preference,
                    onTap: () => controller.setPreference(preference),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 7),
          Text(
            'Automatic uses dark mode from 7 PM to 7 AM.',
            style: PixelText.body(size: 11, color: colors.textMid),
          ),
        ],
      ),
    );
  }
}

class _AppearanceChoice extends StatelessWidget {
  const _AppearanceChoice({
    required this.preference,
    required this.selected,
    required this.onTap,
  });

  final AppThemePreference preference;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final label = switch (preference) {
      AppThemePreference.automatic => 'AUTO',
      AppThemePreference.light => 'LIGHT',
      AppThemePreference.dark => 'DARK',
    };
    return Semantics(
      button: true,
      selected: selected,
      label: '$label appearance',
      child: InkWell(
        key: Key('appearance-${preference.name}'),
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
          decoration: BoxDecoration(
            color: selected ? colors.accent : colors.parchmentDark,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? colors.roofEdge : colors.parchmentBorder,
              width: 1.5,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: colors.buttonShadow,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: PixelText.title(
              size: 11,
              color: selected ? colors.buttonText : colors.textMid,
            ),
          ),
        ),
      ),
    );
  }
}

/// The permanent way back into step access (spec §5.2). Invisible while steps
/// are connected, exactly like [_NotificationToggle] is invisible once
/// notifications are resolved — settings rows that only appear when they have
/// something to fix.
///
/// It re-runs the permission request first and only falls back to the OS
/// settings deep link if that returns nothing, because a prompt the user can
/// actually answer is always the shorter path.
class _ConnectHealthRow extends StatefulWidget {
  const _ConnectHealthRow({required this.authService, this.healthService});

  final AuthService authService;
  final HealthService? healthService;

  @override
  State<_ConnectHealthRow> createState() => _ConnectHealthRowState();
}

class _ConnectHealthRowState extends State<_ConnectHealthRow> {
  late final HealthService _health = widget.healthService ?? HealthService();
  final OnboardingStateService _onboardingState = OnboardingStateService();
  bool _connected = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final authorized = await _health.restoreHealthAuthState();
    final escaped = await _onboardingState.escapedHealthGate();
    final inconclusive = await _onboardingState.probeInconclusive();
    if (!mounted) return;
    setState(() => _connected = authorized && !escaped && !inconclusive);
  }

  Future<void> _connect() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await _health.setUpHealthAccess();
      if (result == HealthSetupResult.authorized) {
        await _onboardingState.setEscapedHealthGate(false);
        await _onboardingState.clearProbeInconclusive();
        if (mounted) setState(() => _connected = true);
        return;
      }
      // Denied, inconclusive, or Health Connect missing: the prompt can't
      // resolve this, so hand the user to the OS surface that can.
      await _health.openPlatformHealthSettings();
    } catch (_) {
      // Nothing to report beyond the row staying visible.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_connected) return const SizedBox.shrink();
    return PillButton(
      key: const Key('settings-connect-health'),
      label: _busy ? 'CONNECTING...' : 'CONNECT STEPS',
      variant: PillButtonVariant.secondary,
      fontSize: 13,
      fullWidth: true,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      onPressed: _busy ? null : _connect,
    );
  }
}

class _NotificationToggle extends StatefulWidget {
  final NotificationService notificationService;
  final String? authToken;

  const _NotificationToggle({
    required this.notificationService,
    required this.authToken,
  });

  @override
  State<_NotificationToggle> createState() => _NotificationToggleState();
}

class _NotificationToggleState extends State<_NotificationToggle> {
  bool? _granted;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = await widget.notificationService.getPermissionState();
    if (mounted) setState(() => _granted = state ?? false);
  }

  Future<void> _enable() async {
    final granted = await widget.notificationService.requestPermission(
      widget.authToken,
    );
    if (mounted) setState(() => _granted = granted);
  }

  @override
  Widget build(BuildContext context) {
    if (_granted == null) return const SizedBox.shrink();

    final label = _granted! ? 'NOTIFICATIONS ON' : 'ENABLE NOTIFICATIONS';

    return PillButton(
      label: label,
      variant: PillButtonVariant.secondary,
      fontSize: 13,
      fullWidth: true,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      onPressed: _granted! ? null : _enable,
    );
  }
}

/// Toggles the evening "your daily box is waiting" reminder pushes (spec §7).
/// Mirrors the leaderboard visibility toggle: optimistic flip, revert on backend
/// failure. Backed by the additive `/notifications/preferences` API (§9.1):
/// - Reads the stored preference only when OS push permission is granted;
///   defaults ON when the field/endpoint is unavailable (older backend).
/// - When OS permission is denied/absent, shows off + disabled with guidance
///   and never re-triggers the OS prompt.
class _DailyRewardReminderToggle extends StatefulWidget {
  final AuthService authService;
  final NotificationService notificationService;
  final BackendApiService backendApiService;

  const _DailyRewardReminderToggle({
    required this.authService,
    required this.notificationService,
    required this.backendApiService,
  });

  @override
  State<_DailyRewardReminderToggle> createState() =>
      _DailyRewardReminderToggleState();
}

class _DailyRewardReminderToggleState
    extends State<_DailyRewardReminderToggle> {
  bool? _osGranted;
  bool _enabled = true;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final granted = await widget.notificationService.getPermissionState();
    var enabled = true;
    // Only consult the backend preference when OS notifications are on — a
    // denied user can't receive these regardless, so we show the row off.
    if (granted == true) {
      final token = widget.authService.authToken;
      if (token != null && token.isNotEmpty) {
        try {
          enabled = await widget.backendApiService
              .fetchDailyRewardRemindersEnabled(identityToken: token);
        } catch (_) {
          // Old backend / offline: default ON (the documented default) rather
          // than crashing or silently flipping the displayed value.
          enabled = true;
        }
      }
    }
    if (mounted) {
      setState(() {
        _osGranted = granted;
        _enabled = enabled;
        _ready = true;
      });
    }
  }

  Future<void> _toggle(bool value) async {
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) return;

    final previous = _enabled;
    setState(() => _enabled = value); // optimistic
    try {
      final persisted = await widget.backendApiService
          .updateDailyRewardRemindersEnabled(
            identityToken: token,
            enabled: value,
          );
      if (mounted) setState(() => _enabled = persisted);
    } catch (_) {
      if (mounted) setState(() => _enabled = previous); // revert on failure
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SizedBox.shrink();
    final granted = _osGranted == true;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      decoration: BoxDecoration(
        color: AppColors.of(context).parchmentLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.of(context).parchmentBorder,
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Remind me to open my daily box',
                  style: PixelText.body(
                    size: 13,
                    color: AppColors.of(context).textDark,
                  ),
                ),
                if (!granted) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Turn on notifications to get reminders',
                    style: PixelText.body(
                      size: 11,
                      color: AppColors.of(context).textMid,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          PixelSwitch(
            // Off + disabled when OS permission isn't granted; no re-prompt.
            value: granted && _enabled,
            onChanged: granted ? _toggle : null,
          ),
        ],
      ),
    );
  }
}
