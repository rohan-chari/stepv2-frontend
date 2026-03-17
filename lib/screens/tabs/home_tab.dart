import 'package:flutter/material.dart';

import '../../models/step_data.dart';
import '../../services/auth_service.dart';
import '../../styles.dart';
import '../../widgets/content_board.dart';
import '../../widgets/game_button.dart';
import '../display_name_screen.dart';

class HomeTab extends StatelessWidget {
  final StepData? stepData;
  final bool isLoading;
  final String? error;
  final int? stepGoal;
  final bool healthAuthorized;
  final bool? notificationsState; // null = not prompted, true = granted, false = denied
  final String? displayName;
  final AuthService authService;
  final Future<void> Function() onRefresh;
  final VoidCallback onEnableHealth;
  final VoidCallback onEnableNotifications;
  final VoidCallback onSetStepGoal;
  final VoidCallback onDisplayNameChanged;

  const HomeTab({
    super.key,
    required this.stepData,
    required this.isLoading,
    required this.error,
    required this.stepGoal,
    required this.healthAuthorized,
    required this.notificationsState,
    required this.displayName,
    required this.authService,
    required this.onRefresh,
    required this.onEnableHealth,
    required this.onEnableNotifications,
    required this.onSetStepGoal,
    required this.onDisplayNameChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (!healthAuthorized) {
      return _buildPermissionPrompt(context);
    }

    if (notificationsState == null) {
      return _buildNotificationPrompt();
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppColors.accent,
      backgroundColor: AppColors.parchment,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: [
                    const SizedBox(height: 24),
                    // Step count
                    _buildStepDisplay(),
                    const SizedBox(height: 24),
                    // Progress bar
                    if (stepGoal != null &&
                        stepGoal! > 0 &&
                        stepData != null &&
                        !isLoading)
                      _buildProgressBar(),
                    const SizedBox(height: 24),
                    // Tips or setup prompts
                    if (displayName == null || stepGoal == null)
                      _buildSetupPrompts(context)
                    else
                      _buildTips(),
                    const Spacer(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepDisplay() {
    if (isLoading && stepData == null) {
      return const SizedBox(
        width: 36,
        height: 36,
        child: CircularProgressIndicator(
          color: AppColors.accent,
          strokeWidth: 3,
        ),
      );
    }

    if (error != null) {
      return Text(
        error!,
        style: PixelText.body(size: 13, color: AppColors.error),
        textAlign: TextAlign.center,
      );
    }

    final steps = stepData?.steps ?? 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'TODAY\'S STEPS',
          style: PixelText.title(size: 14, color: Colors.white).copyWith(
            shadows: [
              const Shadow(
                color: Color(0x50000000),
                offset: Offset(0, 1),
                blurRadius: 3,
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          '$steps',
          style: PixelText.number(size: 56, color: AppColors.accent).copyWith(
            shadows: [
              const Shadow(
                color: Color(0x40000000),
                offset: Offset(0, 2),
                blurRadius: 4,
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
        if (stepGoal != null) ...[
          const SizedBox(height: 2),
          Text(
            '/ $stepGoal',
            style: PixelText.body(size: 18, color: Colors.white).copyWith(
              shadows: [
                const Shadow(
                  color: Color(0x60000000),
                  offset: Offset(0, 1),
                  blurRadius: 3,
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  Widget _buildProgressBar() {
    final steps = stepData?.steps ?? 0;
    final progress = (steps / stepGoal!).clamp(0.0, 1.0);
    final pct = (progress * 100).round();

    return Column(
      children: [
        Container(
          height: 12,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: progress,
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.accent, AppColors.accentLight],
                  ),
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '$pct% of daily goal',
          style: PixelText.body(size: 12, color: Colors.white).copyWith(
            shadows: [
              const Shadow(
                color: Color(0x50000000),
                offset: Offset(0, 1),
                blurRadius: 2,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTips() {
    return ContentBoard(
      width: double.infinity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'EXPLORE',
            style: PixelText.title(size: 14, color: AppColors.textDark),
          ),
          const SizedBox(height: 12),
          _buildTipRow(Icons.emoji_events_rounded, 'Challenges',
              'Compete with friends'),
          const SizedBox(height: 8),
          _buildTipRow(
              Icons.people_rounded, 'Friends', 'Add friends & see their steps'),
          const SizedBox(height: 8),
          _buildTipRow(
              Icons.settings_rounded, 'Settings', 'Update goal & profile'),
          const SizedBox(height: 10),
          Text(
            'Pull down to refresh steps',
            style: PixelText.body(size: 11, color: AppColors.textMid),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildTipRow(IconData icon, String title, String subtitle) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.textMid),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: PixelText.body(size: 13, color: AppColors.textDark),
              ),
              Text(
                subtitle,
                style: PixelText.body(size: 11, color: AppColors.textMid),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPermissionPrompt(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(left: 32, right: 32, top: 80),
        child: Column(
          children: [
            Text(
              'HEALTH DATA',
              style: PixelText.title(size: 20, color: Colors.white).copyWith(
                shadows: [
                  const Shadow(
                    color: Color(0x60000000),
                    offset: Offset(0, 2),
                    blurRadius: 4,
                  ),
                ],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            Text(
              'Step Tracker needs access to your health data to count your daily steps.\n\n'
              "That's all we use - just your step count.",
              style: PixelText.body(size: 14, color: Colors.white).copyWith(
                shadows: [
                  const Shadow(
                    color: Color(0x60000000),
                    offset: Offset(0, 1),
                    blurRadius: 3,
                  ),
                ],
              ),
              textAlign: TextAlign.center,
            ),
            if (error != null) ...[
              const SizedBox(height: 14),
              Text(
                error!,
                style: PixelText.body(size: 13, color: AppColors.error),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 24),
            if (isLoading)
              const CircularProgressIndicator(color: AppColors.accent)
            else
              GameButton(label: 'ENABLE', onPressed: onEnableHealth),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationPrompt() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(left: 32, right: 32, top: 80),
        child: Column(
          children: [
            Text(
              'NOTIFICATIONS',
              style: PixelText.title(size: 20, color: Colors.white).copyWith(
                shadows: [
                  const Shadow(
                    color: Color(0x60000000),
                    offset: Offset(0, 2),
                    blurRadius: 4,
                  ),
                ],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            Text(
              'Get notified when a friend challenges you to a step battle!\n\n'
              'We\u2019ll only send important updates \u2014 no spam.',
              style: PixelText.body(size: 14, color: Colors.white).copyWith(
                shadows: [
                  const Shadow(
                    color: Color(0x60000000),
                    offset: Offset(0, 1),
                    blurRadius: 3,
                  ),
                ],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            GameButton(label: 'ENABLE', onPressed: onEnableNotifications),
          ],
        ),
      ),
    );
  }

  Widget _buildSetupPrompts(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (displayName == null)
          SizedBox(
            width: double.infinity,
            child: GameButton(
              label: 'SET DISPLAY NAME',
              fontSize: 14,
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => DisplayNameScreen(
                      authService: authService,
                    ),
                  ),
                );
                onDisplayNameChanged();
              },
            ),
          ),
        if (displayName == null) const SizedBox(height: 10),
        if (stepGoal == null)
          SizedBox(
            width: double.infinity,
            child: GameButton(
              label: 'SET STEP GOAL',
              fontSize: 14,
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              onPressed: onSetStepGoal,
            ),
          ),
      ],
    );
  }
}
