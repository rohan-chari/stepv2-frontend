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

  /// Item 10 — absolute-URL variant of [_openUrl]. The social links point at
  /// third-party sites, so they must NOT be prefixed with the backend base URL
  /// the way `/support.html` is.
  Future<void> _openAbsoluteUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // A device with no browser/app to handle the link must not crash
      // Settings.
      if (mounted) showErrorToast(context, "Couldn't open that link.");
    }
  }

  /// Item 7 — the suggestion box.
  Future<void> _openFeedbackSheet() async {
    final api = widget.backendApiService;
    if (api == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.of(context).parchment,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _FeedbackSheet(
        authService: widget.authService,
        backendApiService: api,
      ),
    );
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
                if (widget.backendApiService != null) ...[
                  _DailyRewardReminderToggle(
                    authService: widget.authService,
                    notificationService: widget.notificationService!,
                    backendApiService: widget.backendApiService!,
                  ),
                  // Item 3 (client half): hides itself entirely when the
                  // backend doesn't know the preference.
                  _StepMilestoneReminderToggle(
                    authService: widget.authService,
                    notificationService: widget.notificationService!,
                    backendApiService: widget.backendApiService!,
                  ),
                ],
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
              // Item 7: above SUPPORT — catch the feedback before it becomes
              // a one-star review. Needs the API service to post anywhere.
              if (widget.backendApiService != null)
                PillButton(
                  key: const Key('settings-send-feedback'),
                  label: 'SEND FEEDBACK',
                  variant: PillButtonVariant.secondary,
                  fontSize: 13,
                  fullWidth: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  onPressed: _openFeedbackSheet,
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
          // Item 10 — COMMUNITY, between HELP & LEGAL and ACCOUNT. TikTok is
          // deferred until the account exists; the layout takes a third row
          // without changes.
          const SizedBox(height: 24),
          _SettingsSection(
            sectionKey: const Key('settings-section-community'),
            title: 'COMMUNITY',
            icon: Icons.favorite_rounded,
            children: [
              _SocialRow(
                rowKey: const Key('settings-social-instagram'),
                glyph: 'IG',
                platform: 'Instagram',
                handle: '@bara.steps',
                onTap: () =>
                    _openAbsoluteUrl('https://instagram.com/bara.steps'),
              ),
              _SocialRow(
                rowKey: const Key('settings-social-x'),
                glyph: 'X',
                platform: 'X',
                handle: '@barastepz',
                onTap: () => _openAbsoluteUrl('https://x.com/barastepz'),
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

/// Item 10 — one social-platform row: glyph, platform name, handle, chevron.
///
/// GLYPH NOTE: the spec calls for the official monochrome brand glyphs as
/// bundled PNGs. Those assets are not in the repo, and brand marks must not be
/// hand-drawn or pixel-restyled (they are trademarks, not capybara art). Until
/// the official PNGs are dropped in, the glyph is a short monogram set in the
/// app's own pixel type — no trademark reproduced. Swapping in an image is a
/// one-line change here.
///
/// Every colour resolves through [AppColors.of] so the row flips correctly at
/// night (the 07-23 ink trap: a hardcoded light-mode ink is invisible on the
/// dark parchment).
class _SocialRow extends StatelessWidget {
  const _SocialRow({
    required this.rowKey,
    required this.glyph,
    required this.platform,
    required this.handle,
    required this.onTap,
  });

  final Key rowKey;
  final String glyph;
  final String platform;
  final String handle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Semantics(
      button: true,
      label: '$platform, $handle',
      child: InkWell(
        key: rowKey,
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: colors.parchmentLight,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.parchmentBorder, width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.ink.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: colors.ink.withValues(alpha: 0.35),
                    width: 1.5,
                  ),
                ),
                child: Text(
                  glyph,
                  style: PixelText.title(size: 12, color: colors.ink),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      platform,
                      style: PixelText.body(size: 13, color: colors.textDark),
                    ),
                    Text(
                      handle,
                      style: PixelText.body(size: 11, color: colors.textMid),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.open_in_new_rounded,
                size: 15,
                color: colors.textMid,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Item 7 — the suggestion sheet. Offline keeps the text and offers a retry;
/// the user never loses what they typed.
class _FeedbackSheet extends StatefulWidget {
  const _FeedbackSheet({
    required this.authService,
    required this.backendApiService,
  });

  final AuthService authService;
  final BackendApiService backendApiService;

  @override
  State<_FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<_FeedbackSheet> {
  static const int _maxChars = 2000;

  final TextEditingController _controller = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) return;

    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.backendApiService.submitSuggestion(
        identityToken: token,
        text: text,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      // The toast belongs to the screen underneath, which outlives the sheet.
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        // Keep the text. The retry button re-posts exactly what they wrote.
        _error = e.statusCode == 429
            ? "That's plenty for today — thanks! Try again tomorrow."
            : "Couldn't send that. Check your connection and try again.";
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = "Couldn't send that. Check your connection and try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final length = _controller.text.characters.length;
    final tooLong = length > _maxChars;
    final canSend = _controller.text.trim().isNotEmpty && !tooLong && !_sending;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        key: const Key('feedback-sheet'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'SEND FEEDBACK',
                textAlign: TextAlign.center,
                style: PixelText.title(size: 17, color: colors.textDark),
              ),
              const SizedBox(height: 4),
              Text(
                'Ideas, bugs, gripes — we read every one.',
                textAlign: TextAlign.center,
                style: PixelText.body(size: 12, color: colors.textMid),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('feedback-input'),
                controller: _controller,
                autofocus: true,
                maxLines: 5,
                minLines: 3,
                enabled: !_sending,
                textCapitalization: TextCapitalization.sentences,
                style: PixelText.body(size: 14, color: colors.textDark),
                decoration: InputDecoration(
                  hintText: 'What would make Bara better?',
                  hintStyle: PixelText.body(size: 13, color: colors.textMid),
                  filled: true,
                  fillColor: colors.parchmentLight,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: colors.parchmentBorder,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '$length / $_maxChars',
                  style: PixelText.body(
                    size: 11,
                    color: tooLong ? colors.error : colors.textMid,
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 4),
                Text(
                  _error!,
                  key: const Key('feedback-error'),
                  style: PixelText.body(size: 12, color: colors.error),
                ),
              ],
              const SizedBox(height: 10),
              PillButton(
                key: const Key('feedback-submit'),
                // The label becomes RETRY once a send has failed, so the
                // button says what it will do rather than repeating itself.
                label: _error == null ? 'SUBMIT' : 'RETRY',
                variant: PillButtonVariant.primary,
                fullWidth: true,
                loading: _sending,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                onPressed: canSend ? _submit : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Item 3 (client half) — the evening milestone-coin reminder toggle.
///
/// Mirrors [_DailyRewardReminderToggle] but with one critical difference: it
/// HIDES ITSELF when the backend's preferences payload doesn't carry
/// `stepMilestoneRemindersEnabled`. A switch whose PATCH the server silently
/// drops is worse than no switch, and the backend rolls out independently of
/// this build.
class _StepMilestoneReminderToggle extends StatefulWidget {
  const _StepMilestoneReminderToggle({
    required this.authService,
    required this.notificationService,
    required this.backendApiService,
  });

  final AuthService authService;
  final NotificationService notificationService;
  final BackendApiService backendApiService;

  @override
  State<_StepMilestoneReminderToggle> createState() =>
      _StepMilestoneReminderToggleState();
}

class _StepMilestoneReminderToggleState
    extends State<_StepMilestoneReminderToggle> {
  bool? _osGranted;
  bool _enabled = true;
  bool _supported = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final granted = await widget.notificationService.getPermissionState();
    var supported = false;
    var enabled = true;

    final token = widget.authService.authToken;
    if (token != null && token.isNotEmpty) {
      try {
        final prefs = await widget.backendApiService
            .fetchNotificationPreferences(identityToken: token);
        // Presence, not truthiness — that's the whole point.
        supported = prefs.containsKey('stepMilestoneRemindersEnabled');
        final value = prefs['stepMilestoneRemindersEnabled'];
        enabled = value is bool ? value : true;
      } catch (_) {
        supported = false;
      }
    }

    if (mounted) {
      setState(() {
        _osGranted = granted;
        _enabled = enabled;
        _supported = supported;
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
          .updateStepMilestoneRemindersEnabled(
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
    if (!_ready || !_supported) return const SizedBox.shrink();
    final granted = _osGranted == true;

    return Container(
      key: const Key('settings-milestone-reminder-toggle'),
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
                  'Remind me to collect step milestone coins',
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
            value: granted && _enabled,
            onChanged: granted ? _toggle : null,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        PillButton(
          key: const Key('settings-connect-health'),
          label: _busy ? 'CONNECTING...' : 'CONNECT STEPS',
          variant: PillButtonVariant.secondary,
          fontSize: 13,
          fullWidth: true,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          onPressed: _busy ? null : _connect,
        ),
        const SizedBox(height: 7),
        // Item 6 (batch 2026-08-08): this row used to be a bare button asking
        // for health access with no explanation of what we'd do with it. Same
        // copy as the onboarding gate, and just as truthful — we DO store step
        // counts server-side, so it never claims we collect nothing.
        Text(
          key: const Key('settings-health-privacy-copy'),
          'Bara only reads your step count — never your routes, workouts, '
          'heart rate, or location. Your steps are used for races and nothing '
          'else, and we never sell your data.',
          style: PixelText.body(size: 11, color: AppColors.of(context).textMid),
        ),
      ],
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
    // OS truth, not the cached flag — the cache can say "granted" long after
    // a reinstall/denial has silently killed pushes.
    final state = await widget.notificationService.getSystemPermissionState();
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
