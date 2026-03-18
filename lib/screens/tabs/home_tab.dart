import 'package:flutter/material.dart';

import '../../models/step_data.dart';
import '../../services/auth_service.dart';
import '../../styles.dart';
import '../../widgets/content_board.dart';
import '../../widgets/pill_button.dart';
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

  @override
  Widget build(BuildContext context) {
    final String contentKey;
    if (!healthAuthorized) {
      contentKey = 'health';
    } else if (notificationsState == null) {
      contentKey = 'notifications';
    } else {
      contentKey = 'home';
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      transitionBuilder: (Widget child, Animation<double> animation) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1.0, 0.0),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          )),
          child: child,
        );
      },
      child: KeyedSubtree(
        key: ValueKey(contentKey),
        child: _buildCurrentContent(context),
      ),
    );
  }

  Widget _buildCurrentContent(BuildContext context) {
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
          SliverToBoxAdapter(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: [
                    const SizedBox(height: 24),
                    _buildStepDisplay(),
                    const SizedBox(height: 24),
                    if (stepGoal != null &&
                        stepGoal! > 0 &&
                        stepData != null &&
                        !isLoading)
                      _buildProgressBar(),
                    if (displayName == null || stepGoal == null) ...[
                      const SizedBox(height: 24),
                      _buildSetupPrompts(context),
                    ],
                    if (_hasActiveChallenge) ...[
                      const SizedBox(height: 20),
                      _buildChallengeCard(context),
                    ],
                    if (friendsSteps.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _buildFriendsLeaderboard(),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      'Pull down to refresh',
                      style: PixelText.body(size: 11, color: AppColors.textMid),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 120),
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
          'TODAY\u2019S STEPS',
          style: PixelText.title(size: 14, color: AppColors.textDark).copyWith(
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
            style:
                PixelText.body(size: 18, color: AppColors.textDark).copyWith(
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
                    colors: [AppColors.pillGreen, AppColors.pillGreenDark],
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
          style: PixelText.body(size: 12, color: AppColors.textDark).copyWith(
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

  Widget _buildChallengeCard(BuildContext context) {
    final challenge =
        currentChallenge!['challenge'] as Map<String, dynamic>? ?? {};
    final instances = currentChallenge!['instances'] as List? ?? [];
    final weekOfStr = currentChallenge!['weekOf'];

    // Calculate days remaining
    String daysText = '';
    if (weekOfStr != null) {
      try {
        final weekOf = DateTime.parse(weekOfStr.toString());
        final endDate = weekOf.add(const Duration(days: 7));
        final remaining = endDate.difference(DateTime.now()).inDays;
        if (remaining > 0) {
          daysText = '$remaining day${remaining == 1 ? '' : 's'} left';
        } else {
          daysText = 'Ends today';
        }
      } catch (_) {}
    }

    // Find the first active instance to feature, or fallback to first instance
    Map<String, dynamic>? featuredInstance;
    for (final i in instances) {
      final inst = i as Map<String, dynamic>;
      if (inst['status'] == 'ACTIVE') {
        featuredInstance = inst;
        break;
      }
    }
    featuredInstance ??=
        instances.isNotEmpty ? instances.first as Map<String, dynamic> : null;

    if (featuredInstance == null) return const SizedBox.shrink();

    final myUserId = authService.userId ?? '';
    final userA = featuredInstance['userA'] as Map<String, dynamic>?;
    final userB = featuredInstance['userB'] as Map<String, dynamic>?;
    String friendName = '???';
    if (userA != null && userA['id'] != myUserId) {
      friendName = userA['displayName'] as String? ?? '???';
    } else if (userB != null) {
      friendName = userB['displayName'] as String? ?? '???';
    }

    final status = featuredInstance['status'] as String? ?? '';
    final stakeStatus = featuredInstance['stakeStatus'] as String? ?? '';
    final isActive = status == 'ACTIVE' || stakeStatus == 'AGREED';

    // Get step counts from progress data
    int mySteps = 0;
    int theirSteps = 0;
    if (activeChallengeProgress != null && isActive) {
      final pUserA =
          activeChallengeProgress!['userA'] as Map<String, dynamic>?;
      final pUserB =
          activeChallengeProgress!['userB'] as Map<String, dynamic>?;
      if (pUserA != null && pUserB != null) {
        final aId = pUserA['userId'] as String? ?? '';
        if (aId == myUserId) {
          mySteps = pUserA['totalSteps'] as int? ?? 0;
          theirSteps = pUserB['totalSteps'] as int? ?? 0;
        } else {
          mySteps = pUserB['totalSteps'] as int? ?? 0;
          theirSteps = pUserA['totalSteps'] as int? ?? 0;
        }
      }
    }

    // Stake name
    String? stakeName;
    if (isActive) {
      stakeName = (featuredInstance['stake']
          as Map<String, dynamic>?)?['name'] as String?;
    } else {
      stakeName = (featuredInstance['proposedStake']
          as Map<String, dynamic>?)?['name'] as String?;
    }

    return GestureDetector(
      onTap: () {
        Navigator.of(context)
            .push<bool>(MaterialPageRoute(
              builder: (context) => ChallengeDetailScreen(
                authService: authService,
                instance: featuredInstance!,
                challenge: challenge,
              ),
            ))
            .then((_) => onChallengeChanged());
      },
      child: ContentBoard(
        width: double.infinity,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'COMPETITION',
                  style: PixelText.title(size: 13, color: AppColors.accent),
                ),
                if (daysText.isNotEmpty)
                  Text(
                    daysText,
                    style: PixelText.body(size: 12, color: AppColors.textMid),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'vs $friendName',
              style: PixelText.title(size: 16, color: AppColors.textDark),
              textAlign: TextAlign.center,
            ),
            if (stakeName != null) ...[
              const SizedBox(height: 4),
              Text(
                stakeName,
                style: PixelText.body(size: 12, color: AppColors.textMid),
                textAlign: TextAlign.center,
              ),
            ],
            if (isActive && activeChallengeProgress != null) ...[
              const SizedBox(height: 12),
              Text(
                'WEEKLY STEPS',
                style: PixelText.title(size: 11, color: AppColors.textMid),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        Text('YOU',
                            style: PixelText.title(
                                size: 11, color: AppColors.textMid)),
                        const SizedBox(height: 2),
                        Text(
                          '$mySteps',
                          style: PixelText.number(
                            size: 22,
                            color: mySteps >= theirSteps
                                ? AppColors.pillGreen
                                : AppColors.textDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text('vs',
                      style: PixelText.body(
                          size: 14, color: AppColors.textMid)),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          friendName.toUpperCase(),
                          style: PixelText.title(
                              size: 11, color: AppColors.textMid),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$theirSteps',
                          style: PixelText.number(
                            size: 22,
                            color: theirSteps > mySteps
                                ? AppColors.pillGreen
                                : AppColors.textDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
            if (!isActive) ...[
              const SizedBox(height: 8),
              _buildStatusBadge(featuredInstance, myUserId),
            ],
            if (instances.length > 1) ...[
              const SizedBox(height: 8),
              Text(
                '+${instances.length - 1} more',
                style: PixelText.body(size: 11, color: AppColors.textMid),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(
      Map<String, dynamic> instance, String myUserId) {
    final status = instance['status'] as String? ?? '';
    final stakeStatus = instance['stakeStatus'] as String? ?? '';
    String label;
    Color color;
    if (status == 'ACTIVE' || stakeStatus == 'AGREED') {
      label = 'ACTIVE';
      color = AppColors.pillGreen;
    } else {
      final proposedById = instance['proposedById'] as String? ?? '';
      final isIncoming = proposedById.isNotEmpty && proposedById != myUserId;
      label = isIncoming ? 'ACCEPT' : 'WAITING';
      color = isIncoming ? AppColors.accent : AppColors.pillGold;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label, style: PixelText.pill(size: 11, color: color)),
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

    return ContentBoard(
      width: double.infinity,
      child: Column(
        children: [
          Text(
            'FRIENDS TODAY',
            style: PixelText.title(size: 13, color: AppColors.accent),
          ),
          const SizedBox(height: 10),
          for (int i = 0; i < topFriends.length; i++)
            _buildLeaderboardRow(i + 1, topFriends[i]),
        ],
      ),
    );
  }

  Widget _buildLeaderboardRow(int rank, Map<String, dynamic> friend) {
    final name = friend['displayName'] as String? ?? '???';
    final steps = friend['steps'] as int? ?? 0;
    final goal = friend['stepGoal'] as int?;
    final progress =
        (goal != null && goal > 0) ? (steps / goal).clamp(0.0, 1.0) : 0.0;
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
                          color: Colors.white.withValues(alpha: 0.3),
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
                      style:
                          PixelText.body(size: 11, color: AppColors.textMid),
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
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(left: 32, right: 32, top: 80),
        child: Column(
          children: [
            Text(
              'HEALTH DATA',
              style:
                  PixelText.title(size: 20, color: AppColors.textDark).copyWith(
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
              style:
                  PixelText.body(size: 14, color: AppColors.textDark).copyWith(
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
              PillButton(
                label: 'ENABLE HEALTH DATA',
                variant: PillButtonVariant.primary,
                onPressed: onEnableHealth,
              ),
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
              style:
                  PixelText.title(size: 20, color: AppColors.textDark).copyWith(
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
              style:
                  PixelText.body(size: 14, color: AppColors.textDark).copyWith(
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
            PillButton(
              label: 'ENABLE NOTIFICATIONS',
              variant: PillButtonVariant.primary,
              onPressed: onEnableNotifications,
            ),
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
          PillButton(
            label: 'SET DISPLAY NAME',
            variant: PillButtonVariant.secondary,
            fontSize: 14,
            fullWidth: true,
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
        if (displayName == null) const SizedBox(height: 10),
        if (stepGoal == null)
          PillButton(
            label: 'SET STEP GOAL',
            variant: PillButtonVariant.secondary,
            fontSize: 14,
            fullWidth: true,
            padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            onPressed: onSetStepGoal,
          ),
      ],
    );
  }
}
