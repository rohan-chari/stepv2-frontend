import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/backend_config.dart';
import '../../models/loadable.dart';
import '../../models/step_data.dart';
import '../../services/auth_service.dart';
import '../../services/backend_api_service.dart';
import '../../services/notification_service.dart';
import '../../styles.dart';
import '../../widgets/arcade_fx.dart';
import '../../tutorial/tutorial_screen.dart';
import '../../utils/at_name.dart';
import '../../widgets/ad_banner_slot.dart';
import '../../widgets/app_avatar.dart';
import '../../widgets/error_toast.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/pixel_switch.dart';
import '../../widgets/trail_sign.dart';
import '../../widgets/step_calendar.dart';
import '../../widgets/loading_skeleton.dart';
import '../admin_screen.dart';
import '../display_name_screen.dart';
import '../referral_screen.dart';
import '../start_screen.dart';

class ProfileTab extends StatefulWidget {
  final AuthService authService;
  final String? displayName;
  final String? email;
  final VoidCallback onSettingsChanged;
  final Future<void> Function()? onRefresh;
  final BackendApiService? backendApiService;
  final NotificationService? notificationService;
  final StepData? stepData;
  final VoidCallback? onBack;
  final Future<void> Function()? onAddProfilePhoto;
  final Future<void> Function()? onRemoveProfilePhoto;
  final bool showBackButton;

  // Optional tutorial spotlight anchor for the invite-friends button (null in
  // the shipped app; the tutorial passes a key so its overlay can measure it).
  final GlobalKey? tutorialInviteKey;

  const ProfileTab({
    super.key,
    required this.authService,
    required this.displayName,
    required this.onSettingsChanged,
    this.email,
    this.onRefresh,
    this.backendApiService,
    this.notificationService,
    this.stepData,
    this.onBack,
    this.onAddProfilePhoto,
    this.onRemoveProfilePhoto,
    this.showBackButton = true,
    this.tutorialInviteKey,
  });

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  static const _textShadows = [
    Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  late final BackendApiService _api;
  final GlobalKey<_StatsSectionState> _statsKey = GlobalKey();

  void _handleAuthServiceChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _api = widget.backendApiService ?? BackendApiService();
    widget.authService.addListener(_handleAuthServiceChanged);
  }

  @override
  void didUpdateWidget(covariant ProfileTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.authService == widget.authService) return;
    oldWidget.authService.removeListener(_handleAuthServiceChanged);
    widget.authService.addListener(_handleAuthServiceChanged);
  }

  @override
  void dispose() {
    widget.authService.removeListener(_handleAuthServiceChanged);
    super.dispose();
  }

  Future<void> _handleRefresh() async {
    if (widget.onRefresh != null) {
      await widget.onRefresh!();
    }
    await _statsKey.currentState?.loadStats();
  }

  Future<void> _refreshAfterEdit() async {
    if (!mounted) return;
    await _handleRefresh();
  }

  Future<void> _handleAddProfilePhoto() async {
    if (widget.onAddProfilePhoto == null) return;
    await widget.onAddProfilePhoto!.call();
    await _refreshAfterEdit();
  }

  Future<void> _handleRemoveProfilePhoto() async {
    if (widget.onRemoveProfilePhoto == null) return;
    await widget.onRemoveProfilePhoto!.call();
    await _refreshAfterEdit();
  }

  Future<void> _openSettings() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.parchment,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => _SettingsSheet(
        authService: widget.authService,
        notificationService: widget.notificationService,
        onSettingsChanged: widget.onSettingsChanged,
      ),
    );
    // After the settings sheet closes, refetch so any edits inside it
    // (e.g. display name change) are reflected on the profile page.
    await _refreshAfterEdit();
  }

  Future<void> _handleAvatarTap() async {
    final hasPhoto = widget.authService.profilePhotoUrl != null;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.parchment,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'PROFILE PHOTO',
                style: PixelText.title(size: 16, color: AppColors.textDark),
              ),
              const SizedBox(height: 14),
              PillButton(
                label: hasPhoto ? 'CHANGE PHOTO' : 'ADD PHOTO',
                variant: PillButtonVariant.primary,
                fontSize: 13,
                fullWidth: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                onPressed: () => Navigator.of(ctx).pop('change'),
              ),
              if (hasPhoto) ...[
                const SizedBox(height: 10),
                PillButton(
                  label: 'REMOVE PHOTO',
                  variant: PillButtonVariant.accent,
                  fontSize: 13,
                  fullWidth: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  onPressed: () => Navigator.of(ctx).pop('remove'),
                ),
              ],
              const SizedBox(height: 10),
              PillButton(
                label: 'CANCEL',
                variant: PillButtonVariant.secondary,
                fontSize: 13,
                fullWidth: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        ),
      ),
    );

    if (!mounted) return;
    if (action == 'change') {
      await _handleAddProfilePhoto();
    } else if (action == 'remove') {
      await _handleRemoveProfilePhoto();
    }
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final showBackButton = widget.showBackButton && Navigator.canPop(context);
    final bottomPadding = showBackButton ? bottomInset : 77.5 + bottomInset;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const Positioned.fill(
            child: ColoredBox(
              color: AppColors.roofLight,
              child: CustomPaint(
                painter: ArcadeCheckerPainter(drawBottomStripe: false),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(top: topInset, bottom: bottomPadding),
            child: Column(
              children: [
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _handleRefresh,
                    color: AppColors.accent,
                    backgroundColor: AppColors.parchment,
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverToBoxAdapter(
                          child: _buildProfileHeader(
                            showBackButton: showBackButton,
                          ),
                        ),
                        SliverToBoxAdapter(child: _buildBody()),
                      ],
                    ),
                  ),
                ),
                // Bottom banner, in-flow below the list so it reserves its own
                // space (mirrors the leaderboard tab). Collapses to zero size
                // unless banners are enabled AND an ad loads.
                const AdBannerSlot(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileHeader({required bool showBackButton}) {
    final email = widget.email;
    final showEmail =
        email != null && !email.endsWith('@privaterelay.appleid.com');
    final displayName = widget.displayName;
    final hasPhoto = widget.authService.profilePhotoUrl != null;

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.roofLight,
        border: Border(bottom: BorderSide(color: AppColors.roofDark, width: 1)),
      ),
      child: CustomPaint(
        painter: const ArcadeCheckerPainter(drawBottomStripe: false),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showBackButton)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(
                        Icons.arrow_back,
                        color: AppColors.parchment,
                      ),
                      onPressed:
                          widget.onBack ??
                          () {
                            Navigator.of(context).pop();
                          },
                    ),
                  ),
                ),
              Text(
                'PROFILE',
                style: PixelText.title(
                  size: 30,
                  color: AppColors.parchment,
                ).copyWith(shadows: _textShadows),
              ),
              const SizedBox(height: 5),
              Text(
                'Your streak, your stats, and a quick way to manage the basics.',
                style: PixelText.body(
                  size: 15,
                  color: AppColors.parchment.withValues(alpha: 0.92),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: widget.onAddProfilePhoto == null
                        ? null
                        : _handleAvatarTap,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        AppAvatar(
                          name: displayName ?? 'You',
                          imageUrl: widget.authService.profilePhotoUrl,
                          size: 72,
                          isUser: true,
                          borderColor: AppColors.parchment,
                          borderWidth: 2.5,
                        ),
                        if (widget.onAddProfilePhoto != null)
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: AppColors.parchment,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.roofDark,
                                  width: 1.5,
                                ),
                              ),
                              child: Icon(
                                hasPhoto
                                    ? Icons.edit_rounded
                                    : Icons.add_a_photo_rounded,
                                size: 14,
                                color: AppColors.textDark,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (displayName != null && displayName.isNotEmpty)
                          Text(
                            atName(displayName),
                            style: PixelText.title(
                              size: 20,
                              color: AppColors.parchment,
                            ).copyWith(shadows: _textShadows),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        if (showEmail) ...[
                          const SizedBox(height: 4),
                          Text(
                            email,
                            style: PixelText.body(
                              size: 13,
                              color: AppColors.parchment.withValues(
                                alpha: 0.85,
                              ),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: PillButton(
                      label: 'SETTINGS',
                      icon: Icons.settings_rounded,
                      variant: PillButtonVariant.secondary,
                      fontSize: 13,
                      fullWidth: true,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      onPressed: _openSettings,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          StaggerIn(
            index: 0,
            child: Column(
              children: [
                _buildSectionHeader('INVITE FRIENDS'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
                  child: KeyedSubtree(
                    key: widget.tutorialInviteKey,
                    child: PulseGlow(
                      child: PillButton(
                        label: 'INVITE FRIENDS & EARN COINS',
                        icon: Icons.group_add_rounded,
                        // Gold, not green — the primary green pill vanishes
                        // against the checkered green backdrop.
                        variant: PillButtonVariant.secondary,
                        fontSize: 13,
                        fullWidth: true,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ReferralScreen(
                                authService: widget.authService,
                                backendApiService: _api,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          StaggerIn(
            index: 1,
            child: Column(
              children: [
                _buildSectionHeader('STEP CALENDAR'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
                  child: Container(
                    decoration: _profileCardDecoration(),
                    padding: const EdgeInsets.all(10),
                    child: StepCalendar(
                      authService: widget.authService,
                      backendApiService: _api,
                    ),
                  ),
                ),
              ],
            ),
          ),
          StaggerIn(
            index: 2,
            child: Column(
              children: [
                _buildSectionHeader('STATS'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
                  child: Container(
                    decoration: _profileCardDecoration(),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _StatsSection(
                        key: _statsKey,
                        authService: widget.authService,
                        backendApiService: _api,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Parchment game-piece card — same language as the home/races tabs.
  BoxDecoration _profileCardDecoration() {
    return BoxDecoration(
      color: AppColors.parchment,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: AppColors.roofDark.withValues(alpha: 0.55),
        width: 2,
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x66000000),
          offset: Offset(0, 4),
          blurRadius: 0,
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 16,
            decoration: BoxDecoration(
              color: AppColors.pillGold,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: AppColors.pillGoldDark),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: PixelText.title(
              size: 16,
              color: AppColors.parchment,
            ).copyWith(shadows: _textShadows),
          ),
        ],
      ),
    );
  }
}

class _StatsSection extends StatefulWidget {
  final AuthService authService;
  final BackendApiService backendApiService;

  const _StatsSection({
    super.key,
    required this.authService,
    required this.backendApiService,
  });

  @override
  State<_StatsSection> createState() => _StatsSectionState();
}

class _StatsSectionState extends State<_StatsSection> {
  bool _isLoading = true;
  int _thisWeek = 0;
  int _thisMonth = 0;
  int _thisYear = 0;
  int? _avgPerDayWeek;
  int? _avgPerDayMonth;
  int? _avgPerDayYear;
  int _allTime = 0;
  int _streak = 0;
  Loadable<Map<String, dynamic>> _statsState = const Loadable.initial();

  @override
  void initState() {
    super.initState();
    loadStats();
  }

  Future<void> loadStats() async {
    final previous = _statsState.data;
    if (mounted) {
      setState(() {
        _isLoading = true;
        _statsState = previous == null
            ? const Loadable.loading()
            : Loadable.refreshing(previous);
      });
    }

    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statsState = Loadable.error('Not signed in.', data: previous);
        });
      }
      return;
    }

    try {
      final stats = await widget.backendApiService.fetchStats(
        identityToken: token,
      );

      if (mounted) {
        setState(() {
          _thisWeek = (stats['thisWeek'] as num?)?.toInt() ?? 0;
          _thisMonth = (stats['thisMonth'] as num?)?.toInt() ?? 0;
          _thisYear = (stats['thisYear'] as num?)?.toInt() ?? 0;
          _avgPerDayWeek = (stats['avgPerDayWeek'] as num?)?.toInt();
          _avgPerDayMonth = (stats['avgPerDayMonth'] as num?)?.toInt();
          _avgPerDayYear = (stats['avgPerDayYear'] as num?)?.toInt();
          _allTime = (stats['allTime'] as num?)?.toInt() ?? 0;
          _streak = (stats['streak'] as num?)?.toInt() ?? 0;
          _statsState = Loadable.success(stats);
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statsState = Loadable.error('Couldn’t load stats.', data: previous);
        });
      }
    }
  }

  String _formatSteps(int steps) {
    if (steps >= 1000) {
      return '${(steps / 1000).toStringAsFixed(1)}k';
    }
    return '$steps';
  }

  String _formatPlain(int steps) {
    final digits = steps.abs().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(digits[i]);
    }
    return steps < 0 ? '-$buffer' : buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final state = _statsState;
    if (state.shouldShowInitialLoading || (_isLoading && !state.hasData)) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: ListSkeleton(itemCount: 5),
      );
    }

    if (state.isError && !state.hasData) {
      return LoadErrorPanel(
        title: 'Couldn’t load stats',
        message: 'Check your connection and try again.',
        onRetry: loadStats,
      );
    }

    return Column(
      children: [
        if (state.isRefreshing)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: LinearProgressIndicator(
              minHeight: 2,
              color: AppColors.accent,
              backgroundColor: Colors.transparent,
            ),
          ),
        _buildStatRow(
          'Steps/Day This Week',
          _formatPlain(_avgPerDayWeek ?? _thisWeek),
          0,
        ),
        _buildStatRow(
          'Steps/Day This Month',
          _formatPlain(_avgPerDayMonth ?? _thisMonth),
          1,
        ),
        _buildStatRow(
          'Steps/Day This Year',
          _formatPlain(_avgPerDayYear ?? _thisYear),
          2,
        ),
        _buildStatRow('All Time', _formatSteps(_allTime), 3),
        _buildStatRow(
          'Goal Streak',
          '$_streak day${_streak == 1 ? '' : 's'}',
          4,
        ),
      ],
    );
  }

  Widget _buildStatRow(String label, String value, int index) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 14),
      decoration: BoxDecoration(
        color: index.isOdd
            ? AppColors.parchmentDark.withValues(alpha: 0.45)
            : Colors.transparent,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: PixelText.body(size: 16, color: AppColors.textMid),
            ),
          ),
          Text(
            value,
            style: PixelText.title(size: 18, color: AppColors.textDark),
          ),
        ],
      ),
    );
  }
}

class _SettingsSheet extends StatefulWidget {
  final AuthService authService;
  final NotificationService? notificationService;
  final VoidCallback onSettingsChanged;

  const _SettingsSheet({
    required this.authService,
    this.notificationService,
    required this.onSettingsChanged,
  });

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
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
                style: PixelText.title(size: 18, color: AppColors.textDark),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                'This permanently deletes your account, step history, '
                'friends, and coins.',
                style: PixelText.body(size: 14, color: AppColors.textMid),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'Coins held in active races are forfeited to the race pot. '
                'This cannot be undone.',
                style: PixelText.body(size: 13, color: AppColors.textMid),
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
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'SETTINGS',
            style: PixelText.title(size: 18, color: AppColors.textDark),
          ),
          const SizedBox(height: 16),
          PillButton(
            label: 'EDIT DISPLAY NAME',
            variant: PillButtonVariant.secondary,
            fontSize: 13,
            fullWidth: true,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            onPressed: () async {
              Navigator.of(context).pop();
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) =>
                      DisplayNameScreen(authService: widget.authService),
                ),
              );
              widget.onSettingsChanged();
            },
          ),
          const SizedBox(height: 10),
          if (widget.notificationService != null) ...[
            _NotificationToggle(
              notificationService: widget.notificationService!,
              authToken: widget.authService.authToken,
            ),
            const SizedBox(height: 10),
          ],
          _LeaderboardVisibilityToggle(authService: widget.authService),
          const SizedBox(height: 10),
          if (widget.authService.isAdmin) ...[
            PillButton(
              label: 'ADMIN TOOLS',
              variant: PillButtonVariant.secondary,
              fontSize: 13,
              fullWidth: true,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              onPressed: () async {
                Navigator.of(context).pop();
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) =>
                        AdminScreen(authService: widget.authService),
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
          ],
          PillButton(
            label: 'VIEW TUTORIAL',
            variant: PillButtonVariant.secondary,
            fontSize: 13,
            fullWidth: true,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            onPressed: () async {
              Navigator.of(context).pop();
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      TutorialScreen(authService: widget.authService),
                  fullscreenDialog: true,
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          PillButton(
            label: 'SUPPORT',
            variant: PillButtonVariant.secondary,
            fontSize: 13,
            fullWidth: true,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            onPressed: () => _openUrl('/support.html'),
          ),
          const SizedBox(height: 10),
          PillButton(
            label: 'PRIVACY POLICY',
            variant: PillButtonVariant.secondary,
            fontSize: 13,
            fullWidth: true,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            onPressed: () => _openUrl('/privacy.html'),
          ),
          const SizedBox(height: 10),
          PillButton(
            label: 'SIGN OUT',
            variant: PillButtonVariant.accent,
            fontSize: 13,
            fullWidth: true,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            onPressed: _signOut,
          ),
          const SizedBox(height: 10),
          PillButton(
            label: 'DELETE ACCOUNT',
            variant: PillButtonVariant.accent,
            fontSize: 13,
            fullWidth: true,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            onPressed: _confirmDeleteAccount,
          ),
        ],
      ),
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

/// Apple-settings-style row toggling whether the user appears on the global
/// leaderboard. Listens to [authService] so it reflects the latest value
/// (including a revert if the backend write fails).
class _LeaderboardVisibilityToggle extends StatefulWidget {
  final AuthService authService;

  const _LeaderboardVisibilityToggle({required this.authService});

  @override
  State<_LeaderboardVisibilityToggle> createState() =>
      _LeaderboardVisibilityToggleState();
}

class _LeaderboardVisibilityToggleState
    extends State<_LeaderboardVisibilityToggle> {
  void _handleChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    widget.authService.addListener(_handleChanged);
  }

  @override
  void dispose() {
    widget.authService.removeListener(_handleChanged);
    super.dispose();
  }

  Future<void> _toggle(bool value) async {
    await widget.authService.updateLeaderboardVisibility(value);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      decoration: BoxDecoration(
        color: AppColors.parchmentLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.parchmentBorder, width: 1.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Hide me from the global leaderboard',
              style: PixelText.body(size: 13, color: AppColors.textDark),
            ),
          ),
          const SizedBox(width: 12),
          PixelSwitch(
            value: widget.authService.hiddenFromLeaderboard,
            onChanged: _toggle,
          ),
        ],
      ),
    );
  }
}
