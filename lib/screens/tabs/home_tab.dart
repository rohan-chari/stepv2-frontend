import 'package:flutter/material.dart';

import '../../models/step_data.dart';
import '../../services/auth_service.dart';
import '../../styles.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/step_progress_ring.dart';
import '../../widgets/tab_layout.dart';
import '../challenge_detail_screen.dart';
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
  });

  bool get _hasActiveChallenge =>
      currentChallenge != null && currentChallenge!['challenge'] != null;

  List<Map<String, dynamic>> get _challengeInstances =>
      (currentChallenge?['instances'] as List?)?.cast<Map<String, dynamic>>() ??
      const [];

  bool get _hasChallengeActivity => _challengeInstances.isNotEmpty;

  bool get _shouldShowHowItWorks =>
      friendsSteps.isEmpty && !_hasChallengeActivity;

  @override
  Widget build(BuildContext context) {
    if (!healthAuthorized) {
      return _buildPermissionPrompt(context);
    }

    if (notificationsState == null) {
      return _buildNotificationPrompt();
    }

    return TabLayout(
      title: 'HOME',
      onRefresh: onRefresh,
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    return Column(
      children: [
        // Steps display
        _buildStepDisplay(),

        // Setup prompts
        if (displayName == null || stepGoal == null) ...[
          _buildDivider(),
          _buildSetupPrompts(context),
        ],

        // Challenge section
        if (_hasActiveChallenge) ...[
          _buildDivider(),
          _buildChallengeSection(context),
        ],

        // Friends leaderboard
        if (friendsSteps.isNotEmpty) ...[
          _buildDivider(),
          _buildFriendsLeaderboard(),
        ],

        if (_shouldShowHowItWorks) ...[
          _buildDivider(),
          _buildHowItWorksSection(),
        ],
      ],
    );
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

  Widget _buildStepDisplay() {
    if (isLoading && stepData == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
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
      return Text(
        error!,
        style: PixelText.body(size: 13, color: AppColors.error),
        textAlign: TextAlign.center,
      );
    }

    final steps = stepData?.steps ?? 0;
    final goal = stepGoal ?? 0;
    final progress = goal > 0 ? steps / goal : 0.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'TODAY\u2019S STEPS',
          style: PixelText.title(size: 14, color: AppColors.textMid),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        if (goal > 0)
          StepProgressRing(
            progress: progress,
            width: 220,
            height: 150,
            child: Text(
              '$steps / $goal',
              style: PixelText.number(size: 28, color: AppColors.accent),
              textAlign: TextAlign.center,
            ),
          )
        else
          Text(
            '$steps',
            style: PixelText.number(size: 36, color: AppColors.accent),
            textAlign: TextAlign.center,
          ),
      ],
    );
  }

  Widget _buildChallengeSection(BuildContext context) {
    final challenge =
        currentChallenge!['challenge'] as Map<String, dynamic>? ?? {};
    final myUserId = authService.userId ?? '';

    return Column(
      children: [
        Text(
          'COMPETITIONS',
          style: PixelText.title(size: 13, color: AppColors.accent),
        ),
        const SizedBox(height: 8),
        if (_challengeInstances.isEmpty)
          Text(
            'No competitions yet. Head to the Challenges tab to start one.',
            style: PixelText.body(size: 13, color: AppColors.textMid),
            textAlign: TextAlign.center,
          )
        else
          for (final i in _challengeInstances)
            _buildChallengeRow(
              context,
              i as Map<String, dynamic>,
              challenge,
              myUserId,
            ),
      ],
    );
  }

  Widget _buildHowItWorksSection() {
    return Column(
      children: [
        Text(
          'HOW BARA WORKS',
          style: PixelText.title(size: 13, color: AppColors.accent),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Bara turns your daily step count into a private weekly competition with friends.',
          style: PixelText.body(size: 13, color: AppColors.textMid),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        _buildGuideCard(
          title: 'TRACK TODAY',
          body:
              'Sync Health data and watch today\u2019s ring fill as your steps come in.',
        ),
        const SizedBox(height: 10),
        _buildGuideCard(
          title: 'BUILD YOUR CREW',
          body:
              'Add friends to unlock the leaderboard and see who is actually hitting their goal.',
        ),
        const SizedBox(height: 10),
        _buildGuideCard(
          title: 'START A STAKED CHALLENGE',
          body:
              'Open Challenges, pick a friend, propose a stake, and let Sunday\u2019s totals settle it.',
        ),
      ],
    );
  }

  Widget _buildGuideCard({required String title, required String body}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.parchmentLight,
        border: Border.all(color: AppColors.parchmentBorder, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: PixelText.title(size: 12, color: AppColors.textDark),
          ),
          const SizedBox(height: 6),
          Text(body, style: PixelText.body(size: 13, color: AppColors.textMid)),
        ],
      ),
    );
  }

  Widget _buildChallengeRow(
    BuildContext context,
    Map<String, dynamic> instance,
    Map<String, dynamic> challenge,
    String myUserId,
  ) {
    final userA = instance['userA'] as Map<String, dynamic>?;
    final userB = instance['userB'] as Map<String, dynamic>?;
    String friendName = '???';
    if (userA != null && userA['id'] != myUserId) {
      friendName = userA['displayName'] as String? ?? '???';
    } else if (userB != null) {
      friendName = userB['displayName'] as String? ?? '???';
    }

    final status = instance['status'] as String? ?? '';
    final stakeStatus = instance['stakeStatus'] as String? ?? '';
    final isActive = status == 'ACTIVE' || stakeStatus == 'AGREED';

    String statusLabel;
    Color statusColor;
    if (isActive) {
      statusLabel = 'ACTIVE';
      statusColor = AppColors.pillGreen;
    } else {
      final proposedById = instance['proposedById'] as String? ?? '';
      final isIncoming = proposedById.isNotEmpty && proposedById != myUserId;
      statusLabel = isIncoming ? 'ACCEPT' : 'WAITING';
      statusColor = isIncoming ? AppColors.accent : AppColors.pillGold;
    }

    return GestureDetector(
      onTap: () {
        Navigator.of(context)
            .push<bool>(
              MaterialPageRoute(
                builder: (context) => ChallengeDetailScreen(
                  authService: authService,
                  instance: instance,
                  challenge: challenge,
                ),
              ),
            )
            .then((_) => onChallengeChanged());
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'vs $friendName',
                style: PixelText.body(size: 13, color: AppColors.textDark),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                statusLabel,
                style: PixelText.pill(size: 10, color: statusColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFriendsLeaderboard() {
    final sorted = List<Map<String, dynamic>>.from(friendsSteps);
    sorted.sort((a, b) {
      final aSteps = a['steps'] as int? ?? 0;
      final aGoal = a['stepGoal'] as int?;
      final bSteps = b['steps'] as int? ?? 0;
      final bGoal = b['stepGoal'] as int?;
      final aPct = (aGoal != null && aGoal > 0)
          ? aSteps / aGoal
          : aSteps / 10000.0;
      final bPct = (bGoal != null && bGoal > 0)
          ? bSteps / bGoal
          : bSteps / 10000.0;
      return bPct.compareTo(aPct);
    });

    final topFriends = sorted.take(5).toList();

    return Column(
      children: [
        Text(
          'FRIENDS TODAY',
          style: PixelText.title(size: 13, color: AppColors.accent),
        ),
        const SizedBox(height: 10),
        for (int i = 0; i < topFriends.length; i++)
          _buildLeaderboardRow(i + 1, topFriends[i]),
      ],
    );
  }

  Widget _buildLeaderboardRow(int rank, Map<String, dynamic> friend) {
    final name = friend['displayName'] as String? ?? '???';
    final steps = friend['steps'] as int? ?? 0;
    final goal = friend['stepGoal'] as int?;
    final progress = (goal != null && goal > 0)
        ? (steps / goal).clamp(0.0, 1.0)
        : 0.0;
    final pct = (progress * 100).round();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              '#$rank',
              style: PixelText.title(size: 12, color: AppColors.textMid),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: PixelText.body(size: 13, color: AppColors.textDark),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 8,
                        decoration: BoxDecoration(
                          color: AppColors.parchmentBorder.withValues(
                            alpha: 0.3,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: progress,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  AppColors.pillGreen,
                                  AppColors.pillGreenDark,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      goal != null && goal > 0 ? '$pct%' : '$steps',
                      style: PixelText.body(size: 11, color: AppColors.textMid),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionPrompt(BuildContext context) {
    return TabLayout(
      title: 'HOME',
      child: Column(
        children: [
          Text(
            'HEALTH DATA',
            style: PixelText.title(size: 20, color: AppColors.textDark),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          Text(
            'Bara needs access to your health data to count your daily steps.\n\n'
            "That's all we use - just your step count.",
            style: PixelText.body(size: 14, color: AppColors.textMid),
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
            PillButton(
              label: 'ENABLE HEALTH DATA',
              variant: PillButtonVariant.primary,
              onPressed: onEnableHealth,
            ),
        ],
      ),
    );
  }

  Widget _buildNotificationPrompt() {
    return TabLayout(
      title: 'HOME',
      child: Column(
        children: [
          Text(
            'NOTIFICATIONS',
            style: PixelText.title(size: 20, color: AppColors.textDark),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          Text(
            'Get notified when a friend challenges you to a step battle!\n\n'
            'We\u2019ll only send important updates \u2014 no spam.',
            style: PixelText.body(size: 14, color: AppColors.textMid),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          PillButton(
            label: 'ENABLE NOTIFICATIONS',
            variant: PillButtonVariant.primary,
            onPressed: onEnableNotifications,
          ),
        ],
      ),
    );
  }

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
        if (displayName == null) const SizedBox(height: 10),
        if (stepGoal == null)
          PillButton(
            label: 'SET STEP GOAL',
            variant: PillButtonVariant.secondary,
            fontSize: 14,
            fullWidth: true,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            onPressed: onSetStepGoal,
          ),
      ],
    );
  }
}
