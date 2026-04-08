import 'package:flutter/material.dart';

import '../../models/step_data.dart';
import '../../services/auth_service.dart';
import '../../services/backend_api_service.dart';
import '../../services/notification_service.dart';
import '../../styles.dart';
import '../../widgets/app_avatar.dart';
import '../../widgets/coin_balance_badge.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/pill_icon_button.dart';
import '../../widgets/retro_card.dart';
import '../../widgets/step_calendar.dart';
import '../admin_challenge_screen.dart';
import '../display_name_screen.dart';
import '../start_screen.dart';
import '../step_goal_screen.dart';

class ProfileTab extends StatefulWidget {
  final AuthService authService;
  final String? displayName;
  final int? stepGoal;
  final String? email;
  final VoidCallback onSettingsChanged;
  final Future<void> Function()? onRefresh;
  final BackendApiService? backendApiService;
  final NotificationService? notificationService;
  final StepData? stepData;
  final VoidCallback? onBack;
  final Future<void> Function()? onAddProfilePhoto;
  final Future<void> Function()? onRemoveProfilePhoto;

  const ProfileTab({
    super.key,
    required this.authService,
    required this.displayName,
    required this.stepGoal,
    required this.onSettingsChanged,
    this.email,
    this.onRefresh,
    this.backendApiService,
    this.notificationService,
    this.stepData,
    this.onBack,
    this.onAddProfilePhoto,
    this.onRemoveProfilePhoto,
  });

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  late final BackendApiService _api;
  final GlobalKey<_StatsSectionState> _statsKey = GlobalKey();

  static const _textShadows = [
    Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  @override
  void initState() {
    super.initState();
    _api = widget.backendApiService ?? BackendApiService();
  }

  Future<void> _showStepGoalDialog() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => StepGoalScreen(authService: widget.authService),
      ),
    );
    if (result == true && mounted) {
      widget.onSettingsChanged();
      _statsKey.currentState?.loadStats();
    }
  }

  Future<void> _handleRefresh() async {
    if (widget.onRefresh != null) {
      await widget.onRefresh!();
    }
    await _statsKey.currentState?.loadStats();
  }

  void _openSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.parchment,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => _SettingsSheet(
        authService: widget.authService,
        notificationService: widget.notificationService,
        onSettingsChanged: widget.onSettingsChanged,
        onShowStepGoalDialog: _showStepGoalDialog,
      ),
    );
  }

  static String _formatNumber(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  static String _formatCompact(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(n % 1000 == 0 ? 0 : 1)}k';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF87CEEB), Color(0xFFB0E0F0), Color(0xFFD4F1F9)],
          ),
        ),
        child: Padding(
          padding: EdgeInsets.only(top: topInset + 12, bottom: bottomInset),
          child: RefreshIndicator(
            onRefresh: _handleRefresh,
            color: AppColors.accent,
            backgroundColor: AppColors.parchment,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildTopStatusBar(),
                        const SizedBox(height: 16),
                        RetroCard(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                          child: Row(
                            children: [
                              AppAvatar(
                                name: widget.displayName ?? 'You',
                                imageUrl: widget.authService.profilePhotoUrl,
                                size: 54,
                                isUser: true,
                                borderColor: AppColors.parchment,
                                borderWidth: 2.5,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (widget.email != null &&
                                        !widget.email!.endsWith('@privaterelay.appleid.com')) ...[
                                      Text(
                                        widget.email!,
                                        style: PixelText.body(size: 14, color: AppColors.textMid),
                                      ),
                                      const SizedBox(height: 4),
                                    ],
                                    if (widget.stepGoal != null)
                                      Text(
                                        'Goal: ${widget.stepGoal} steps/day',
                                        style: PixelText.body(size: 14, color: AppColors.textMid),
                                      ),
                                  ],
                                ),
                              ),
                              PillButton(
                                label: 'SETTINGS',
                                variant: PillButtonVariant.secondary,
                                fontSize: 12,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                onPressed: _openSettings,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        RetroCard(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Expanded(
                                child: PillButton(
                                  label: widget.authService.profilePhotoUrl == null
                                      ? 'ADD PHOTO'
                                      : 'CHANGE PHOTO',
                                  variant: PillButtonVariant.primary,
                                  fontSize: 12,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  onPressed: () => widget.onAddProfilePhoto?.call(),
                                ),
                              ),
                              if (widget.authService.profilePhotoUrl != null) ...[
                                const SizedBox(width: 10),
                                Expanded(
                                  child: PillButton(
                                    label: 'REMOVE PHOTO',
                                    variant: PillButtonVariant.secondary,
                                    fontSize: 12,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    onPressed: () => widget.onRemoveProfilePhoto?.call(),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        RetroCard(
                          padding: const EdgeInsets.all(12),
                          child: StepCalendar(
                            authService: widget.authService,
                            backendApiService: _api,
                          ),
                        ),
                        const SizedBox(height: 16),
                        RetroCard(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                          child: Column(
                            children: [
                              Text(
                                'STATS',
                                style: PixelText.title(size: 16, color: AppColors.textMid),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              _StatsSection(
                                key: _statsKey,
                                authService: widget.authService,
                                backendApiService: _api,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopStatusBar() {
    final steps = widget.stepData?.steps ?? 0;
    final goal = widget.stepGoal ?? 0;
    final stepsStr = _formatNumber(steps);
    final goalStr = goal > 0 ? _formatCompact(goal) : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PillIconButton(
          icon: Icons.arrow_back_rounded,
          size: 36,
          variant: PillButtonVariant.secondary,
          onPressed: () => Navigator.of(context).pop(),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            AppAvatar(
              name: widget.displayName ?? 'You',
              imageUrl: widget.authService.profilePhotoUrl,
              size: 44,
              isUser: true,
              borderColor: AppColors.parchment,
              borderWidth: 2.25,
            ),
            const SizedBox(width: 10),
            if (widget.displayName != null)
              Expanded(
                child: Text(
                  widget.displayName!,
                  style: PixelText.title(size: 26, color: AppColors.textDark)
                      .copyWith(shadows: _textShadows),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const SizedBox(width: 8),
            CoinBalanceBadge(
              coins: widget.authService.coins,
              heldCoins: widget.authService.heldCoins,
            ),
          ],
        ),
        const SizedBox(height: 2),
        if (goalStr != null)
          Text(
            '$stepsStr / $goalStr',
            style: PixelText.number(size: 20, color: AppColors.accent)
                .copyWith(shadows: _textShadows),
          )
        else
          Text(
            stepsStr,
            style: PixelText.number(size: 20, color: AppColors.accent)
                .copyWith(shadows: _textShadows),
          ),
      ],
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
  int _allTime = 0;
  int _streak = 0;

  @override
  void initState() {
    super.initState();
    loadStats();
  }

  Future<void> loadStats() async {
    if (mounted) setState(() => _isLoading = true);

    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final stats = await widget.backendApiService.fetchStats(
        identityToken: token,
      );

      if (mounted) {
        setState(() {
          _thisWeek = stats['thisWeek'] as int? ?? 0;
          _thisMonth = stats['thisMonth'] as int? ?? 0;
          _thisYear = stats['thisYear'] as int? ?? 0;
          _allTime = stats['allTime'] as int? ?? 0;
          _streak = stats['streak'] as int? ?? 0;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatSteps(int steps) {
    if (steps >= 1000) {
      return '${(steps / 1000).toStringAsFixed(1)}k';
    }
    return '$steps';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              color: AppColors.accent,
              strokeWidth: 2,
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        _buildStatRow('This Week', _formatSteps(_thisWeek), 0),
        _buildStatRow('This Month', _formatSteps(_thisMonth), 1),
        _buildStatRow('This Year', _formatSteps(_thisYear), 2),
        _buildStatRow('All Time', _formatSteps(_allTime), 3),
        _buildStatRow('Goal Streak', '$_streak day${_streak == 1 ? '' : 's'}', 4),
      ],
    );
  }

  Widget _buildStatRow(String label, String value, int index) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: index.isOdd
            ? AppColors.parchmentDark.withValues(alpha: 0.3)
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
  final VoidCallback onShowStepGoalDialog;

  const _SettingsSheet({
    required this.authService,
    this.notificationService,
    required this.onSettingsChanged,
    required this.onShowStepGoalDialog,
  });

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
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
    return Padding(
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
          PillButton(
            label: 'EDIT STEP GOAL',
            variant: PillButtonVariant.secondary,
            fontSize: 13,
            fullWidth: true,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            onPressed: () {
              Navigator.of(context).pop();
              widget.onShowStepGoalDialog();
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
          if (widget.authService.isAdmin) ...[
            PillButton(
              label: 'ADMIN CHALLENGE TOOLS',
              variant: PillButtonVariant.secondary,
              fontSize: 13,
              fullWidth: true,
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              onPressed: () async {
                Navigator.of(context).pop();
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => AdminChallengeScreen(
                      authService: widget.authService,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
          ],
          PillButton(
            label: 'SIGN OUT',
            variant: PillButtonVariant.accent,
            fontSize: 13,
            fullWidth: true,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            onPressed: _signOut,
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
