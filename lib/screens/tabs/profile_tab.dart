import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/backend_api_service.dart';
import '../../services/notification_service.dart';
import '../../styles.dart';
import '../../widgets/error_toast.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/pill_icon_button.dart';
import '../../widgets/tab_layout.dart';
import '../../widgets/trail_sign.dart';
import '../admin_challenge_screen.dart';
import '../display_name_screen.dart';
import '../start_screen.dart';

class ProfileTab extends StatefulWidget {
  final AuthService authService;
  final String? displayName;
  final int? stepGoal;
  final String? email;
  final VoidCallback onSettingsChanged;
  final Future<void> Function()? onRefresh;
  final BackendApiService? backendApiService;
  final NotificationService? notificationService;

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
  });

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  late final BackendApiService _api;
  final GlobalKey<_StatsSectionState> _statsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _api = widget.backendApiService ?? BackendApiService();
  }

  Future<void> _showStepGoalDialog() async {
    final currentGoal = widget.authService.stepGoal;
    final controller = TextEditingController(
      text: currentGoal?.toString() ?? '',
    );

    final result = await showDialog<int>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: TrailSign(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'STEP GOAL',
                  style: PixelText.title(size: 18, color: AppColors.textDark),
                ),
                const SizedBox(height: 8),
                Text(
                  'How many steps per day?',
                  style: PixelText.body(size: 14, color: AppColors.textMid),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: PixelText.number(size: 24, color: AppColors.textDark),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppColors.parchmentLight,
                    border: OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.parchmentBorder),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.parchmentBorder),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.accent, width: 2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: PillButton(
                        label: 'CANCEL',
                        variant: PillButtonVariant.secondary,
                        fontSize: 13,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: PillButton(
                        label: 'SAVE',
                        variant: PillButtonVariant.primary,
                        fontSize: 13,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        onPressed: () {
                          final value = int.tryParse(controller.text);
                          if (value != null && value > 0) {
                            Navigator.of(context).pop(value);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (result == null || !mounted) return;

    await widget.authService.updateStepGoal(result);
    widget.onSettingsChanged();

    try {
      final identityToken = widget.authService.authToken;
      if (identityToken != null && identityToken.isNotEmpty) {
        await _api.setStepGoal(identityToken: identityToken, stepGoal: result);
        _statsKey.currentState?.loadStats();
      }
    } catch (e) {
      if (mounted) {
        showErrorToast(
          context,
          'Couldn\u2019t save your step goal. Please try again.',
        );
      }
    }
  }

  Widget _buildDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Container(
        height: 1,
        color: AppColors.parchmentBorder.withValues(alpha: 0.5),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: PixelText.body(size: 12, color: AppColors.textMid),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: PixelText.body(size: 13, color: AppColors.textDark),
            ),
          ),
        ],
      ),
    );
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return TabLayout(
      title: 'PROFILE',
      onRefresh: _handleRefresh,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Gear button
          Align(
            alignment: Alignment.topRight,
            child: PillIconButton(
              icon: Icons.settings_rounded,
              size: 36,
              variant: PillButtonVariant.secondary,
              onPressed: _openSettings,
            ),
          ),
          const SizedBox(height: 8),
          // User info
          Center(
            child: Column(
              children: [
                if (widget.displayName != null)
                  Text(
                    widget.displayName!,
                    style: PixelText.title(size: 20, color: AppColors.accent),
                    textAlign: TextAlign.center,
                  ),
                if (widget.email != null &&
                    !widget.email!.endsWith('@privaterelay.appleid.com')) ...[
                  const SizedBox(height: 4),
                  Text(
                    widget.email!,
                    style: PixelText.body(size: 12, color: AppColors.textMid),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (widget.stepGoal != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Goal: ${widget.stepGoal} steps/day',
                    style: PixelText.body(size: 13, color: AppColors.textMid),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Edit buttons
          Row(
            children: [
              Expanded(
                child: PillButton(
                  label: 'EDIT NAME',
                  variant: PillButtonVariant.secondary,
                  fontSize: 12,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
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
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PillButton(
                  label: 'EDIT GOAL',
                  variant: PillButtonVariant.secondary,
                  fontSize: 12,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  onPressed: _showStepGoalDialog,
                ),
              ),
            ],
          ),

          _buildDivider(),

          // Stats
          Center(
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
  int _wins = 0;
  int _losses = 0;

  @override
  void initState() {
    super.initState();
    loadStats();
  }

  Future<void> loadStats() async {
    if (mounted) {
      setState(() => _isLoading = true);
    }

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
          _wins = stats['wins'] as int? ?? 0;
          _losses = stats['losses'] as int? ?? 0;
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

  Widget _buildStatCard(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.parchmentLight,
          border: Border.all(color: AppColors.parchmentBorder),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: PixelText.number(size: 18, color: AppColors.accent),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: PixelText.body(size: 10, color: AppColors.textMid),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
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
        Row(
          children: [
            _buildStatCard('THIS WEEK', _formatSteps(_thisWeek)),
            const SizedBox(width: 12),
            _buildStatCard('THIS MONTH', _formatSteps(_thisMonth)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildStatCard('THIS YEAR', _formatSteps(_thisYear)),
            const SizedBox(width: 12),
            _buildStatCard('ALL TIME', _formatSteps(_allTime)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildStatCard(
              'GOAL STREAK',
              '$_streak day${_streak == 1 ? '' : 's'}',
            ),
            const SizedBox(width: 12),
            _buildStatCard('RECORD', '$_wins W - $_losses L'),
          ],
        ),
      ],
    );
  }
}

class _SettingsSheet extends StatefulWidget {
  final AuthService authService;
  final NotificationService? notificationService;

  const _SettingsSheet({
    required this.authService,
    this.notificationService,
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
