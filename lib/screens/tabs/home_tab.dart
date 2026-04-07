import 'package:flutter/material.dart';

import '../../models/step_data.dart';
import '../../services/auth_service.dart';
import '../../styles.dart';
import '../../widgets/feature_highlights_row.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/pill_icon_button.dart';
import '../../widgets/goal_track.dart';
import '../../widgets/game_container.dart';
import '../../widgets/spinning_coin.dart';
import '../display_name_screen.dart';

class HomeTab extends StatelessWidget {
  final StepData? stepData;
  final bool isLoading;
  final String? error;
  final int? stepGoal;
  final bool healthAuthorized;
  final bool? notificationsState;
  final String? displayName;
  final AuthService authService;
  final Future<void> Function() onRefresh;
  final VoidCallback onEnableHealth;
  final VoidCallback onEnableNotifications;
  final VoidCallback onSetStepGoal;
  final VoidCallback onDisplayNameChanged;
  final Map<String, dynamic>? currentChallenge;
  final List<Map<String, dynamic>> friendsSteps;
  final Map<String, dynamic>? activeChallengeProgress;
  final VoidCallback onChallengeChanged;
  final VoidCallback? onOpenFriendsTab;
  final VoidCallback? onOpenChallengesTab;
  final VoidCallback? onOpenLeaderboardTab;
  final VoidCallback? onOpenProfile;

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
    required this.currentChallenge,
    required this.friendsSteps,
    this.activeChallengeProgress,
    required this.onChallengeChanged,
    this.onOpenFriendsTab,
    this.onOpenChallengesTab,
    this.onOpenLeaderboardTab,
    this.onOpenProfile,
  });

  @override
  Widget build(BuildContext context) {
    if (!healthAuthorized) {
      return _buildPermissionPrompt(context);
    }

    if (notificationsState == null) {
      return _buildNotificationPrompt();
    }

    final topInset = MediaQuery.of(context).padding.top;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final tabBarHeight = 77.5 + bottomInset;
    final bottomPadding = tabBarHeight;

    return Padding(
      padding: EdgeInsets.only(top: topInset + 12, bottom: bottomPadding),
      child: RefreshIndicator(
        onRefresh: onRefresh,
        color: AppColors.accent,
        backgroundColor: AppColors.parchment,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(
                child: Column(
                  children: [
                    _buildTopStatusBar(),
                    const SizedBox(height: 12),

                    if (displayName == null) ...[
                      _buildSetupPrompts(context),
                      const SizedBox(height: 12),
                    ],

                    _buildGoalTrackSection(),
                    const SizedBox(height: 16),

                    _buildActionButtons(),
                    const SizedBox(height: 16),

                    _buildDailyRewardSlots(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -- Top status bar: name | steps | streak | coins --

  Widget _buildTopStatusBar() {
    final steps = stepData?.steps ?? 0;
    final goal = stepGoal ?? 0;
    final stepsStr = _formatNumber(steps);
    final goalStr = goal > 0 ? _formatCompact(goal) : null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (displayName != null)
                    Flexible(
                      child: Text(
                        displayName!,
                        style: PixelText.title(
                          size: 26,
                          color: AppColors.textDark,
                        ).copyWith(shadows: _textShadows),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  const SizedBox(width: 8),
                  const SpinningCoin(size: 18),
                  const SizedBox(width: 3),
                  Text(
                    '${authService.coins}',
                    style: PixelText.number(
                      size: 16,
                      color: AppColors.coinDark,
                    ).copyWith(shadows: _textShadows),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              if (goalStr != null)
                Text(
                  '$stepsStr / $goalStr',
                  style: PixelText.number(
                    size: 20,
                    color: AppColors.accent,
                  ).copyWith(shadows: _textShadows),
                )
              else
                Text(
                  stepsStr,
                  style: PixelText.number(
                    size: 20,
                    color: AppColors.accent,
                  ).copyWith(shadows: _textShadows),
                ),
            ],
          ),
        ),
        PillIconButton(
          icon: Icons.person_rounded,
          size: 36,
          variant: PillButtonVariant.secondary,
          onPressed: onOpenProfile,
        ),
      ],
    );
  }

  // -- GoalTrack centerpiece --

  Widget _buildGoalTrackSection() {
    if (isLoading && stepData == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(
              color: AppColors.accent,
              strokeWidth: 3,
            ),
          ),
        ),
      );
    }

    if (error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          error!,
          style: PixelText.body(size: 13, color: AppColors.error),
          textAlign: TextAlign.center,
        ),
      );
    }

    final steps = stepData?.steps ?? 0;
    final goal = stepGoal ?? 0;
    final progress = goal > 0 ? steps / goal : 0.0;

    if (goal <= 0) {
      return Column(
        children: [
          Text(
            '$steps',
            style: PixelText.number(size: 36, color: AppColors.accent),
            textAlign: TextAlign.center,
          ),
          Text(
            'steps today',
            style: PixelText.body(size: 14, color: AppColors.textMid),
          ),
        ],
      );
    }

    return GameContainer(
      padding: const EdgeInsets.all(6),
      child: GoalTrack(
        height: 300,
        runners: [
          GoalTrackRunner(
            name: displayName ?? 'You',
            progress: progress,
            isUser: true,
          ),
          for (final friend in friendsSteps)
            GoalTrackRunner(
              name: friend['displayName'] as String? ?? '???',
              progress: _friendGoalProgress(friend),
            ),
        ],
      ),
    );
  }

  // -- Action buttons: CHALLENGE + LEADERBOARD --

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: PillButton(
            label: 'CHALLENGES',
            variant: PillButtonVariant.accent,
            fontSize: 14,
            fullWidth: true,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            onPressed: () => onOpenChallengesTab?.call(),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: PillButton(
            label: 'LEADERBOARD',
            variant: PillButtonVariant.secondary,
            fontSize: 14,
            fullWidth: true,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            onPressed: () => onOpenLeaderboardTab?.call(),
          ),
        ),
      ],
    );
  }

  // -- Daily reward slots --

  Widget _buildDailyRewardSlots() {
    final steps = stepData?.steps ?? 0;
    final goal = stepGoal ?? 0;
    final hitGoal = goal > 0 && steps >= goal;
    final hitDoubleGoal = goal > 0 && steps >= goal * 2;

    return Column(
      children: [
        _DailyRewardCard(
          label: '1x GOAL',
          description: 'Hit your daily step goal',
          reward: '+10 coins',
          unlocked: hitGoal,
        ),
        const SizedBox(height: 10),
        _DailyRewardCard(
          label: '2x GOAL',
          description: 'Double your daily step goal',
          reward: '+10 coins',
          unlocked: hitDoubleGoal,
        ),
      ],
    );
  }

  // -- Setup prompts (kept from original) --

  Widget _buildSetupPrompts(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (displayName == null)
          PillButton(
            label: 'SET DISPLAY NAME',
            variant: PillButtonVariant.secondary,
            fontSize: 14,
            fullWidth: true,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) =>
                      DisplayNameScreen(authService: authService),
                ),
              );
              onDisplayNameChanged();
            },
          ),
      ],
    );
  }

  // -- Permission / notification prompts --

  Widget _buildPermissionPrompt(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            const Spacer(flex: 2),
            Icon(Icons.favorite_rounded, size: 48, color: AppColors.accent),
            const SizedBox(height: 16),
            Text(
              'HEALTH DATA',
              style: PixelText.title(
                size: 24,
                color: AppColors.textDark,
              ).copyWith(shadows: _textShadows),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Bara needs access to your health data to count your daily steps.\n\n'
              "That's all we use - just your step count.",
              style: PixelText.body(
                color: AppColors.textMid,
              ).copyWith(shadows: _textShadows),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            const FeatureHighlightsRow(),
            if (error != null) ...[
              const SizedBox(height: 14),
              Text(
                error!,
                style: PixelText.body(color: AppColors.error),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 32),
            if (isLoading)
              const CircularProgressIndicator(color: AppColors.accent)
            else
              PillButton(
                label: 'ENABLE HEALTH DATA',
                variant: PillButtonVariant.primary,
                fontSize: 16,
                fullWidth: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 48,
                  vertical: 16,
                ),
                onPressed: onEnableHealth,
              ),
            const Spacer(flex: 3),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationPrompt() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            const Spacer(flex: 2),
            Icon(
              Icons.notifications_rounded,
              size: 48,
              color: AppColors.accent,
            ),
            const SizedBox(height: 16),
            Text(
              'NOTIFICATIONS',
              style: PixelText.title(
                size: 24,
                color: AppColors.textDark,
              ).copyWith(shadows: _textShadows),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Get notified when a friend challenges you to a step battle!\n\n'
              'We\u2019ll only send important updates \u2014 no spam.',
              style: PixelText.body(
                color: AppColors.textMid,
              ).copyWith(shadows: _textShadows),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            const FeatureHighlightsRow(),
            const SizedBox(height: 32),
            PillButton(
              label: 'ENABLE NOTIFICATIONS',
              variant: PillButtonVariant.primary,
              fontSize: 16,
              fullWidth: true,
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
              onPressed: onEnableNotifications,
            ),
            const Spacer(flex: 3),
          ],
        ),
      ),
    );
  }

  // -- Helpers --

  static double _friendGoalProgress(Map<String, dynamic> friend) {
    final steps = friend['steps'] as int? ?? 0;
    final goal = friend['stepGoal'] as int?;
    if (goal != null && goal > 0) return (steps / goal).clamp(0.0, 1.0);
    return 0.0;
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
    if (n >= 1000)
      return '${(n / 1000).toStringAsFixed(n % 1000 == 0 ? 0 : 1)}k';
    return '$n';
  }

  static const _textShadows = [
    Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
  ];
}

// -- Daily reward card widget --

class _DailyRewardCard extends StatelessWidget {
  final String label;
  final String description;
  final String reward;
  final bool unlocked;

  const _DailyRewardCard({
    required this.label,
    required this.description,
    required this.reward,
    required this.unlocked,
  });

  @override
  Widget build(BuildContext context) {
    return GameContainer(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      child: Row(
        children: [
          if (unlocked)
            const SpinningCoin(size: 28)
          else
            Icon(
              Icons.lock_rounded,
              size: 28,
              color: AppColors.textMid.withValues(alpha: 0.5),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: PixelText.title(
                    size: 14,
                    color: unlocked ? AppColors.textDark : AppColors.textMid,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: PixelText.body(
                    size: 12,
                    color: unlocked ? AppColors.textDark : AppColors.textMid,
                  ),
                ),
              ],
            ),
          ),
          Text(
            reward,
            style: PixelText.title(
              size: 14,
              color: unlocked ? AppColors.coinDark : AppColors.textMid,
            ),
          ),
        ],
      ),
    );
  }
}
