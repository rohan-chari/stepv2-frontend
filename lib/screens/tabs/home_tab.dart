import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../styles.dart';
import '../../models/step_data.dart';
import '../../services/auth_service.dart';
import '../../widgets/app_avatar.dart';
import '../../widgets/coin_balance_badge.dart';
import '../../widgets/goal_track.dart';
import '../../widgets/home_chrome.dart';
import '../../widgets/home_course_track.dart';
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
  final List<Map<String, dynamic>> equippedAccessories;
  final Map<String, dynamic>? activeChallengeProgress;
  final List<Map<String, dynamic>> leaderboardHighlights;
  final bool leaderboardHighlightsLoading;
  final VoidCallback onChallengeChanged;
  final VoidCallback? onOpenFriendsTab;
  final VoidCallback? onOpenChallengesTab;
  final VoidCallback? onOpenLeaderboardTab;
  final void Function(String leaderboardType, String period)?
  onOpenLeaderboardHighlight;
  final VoidCallback? onOpenProfile;
  final Future<void> Function()? onAddProfilePhoto;
  final Future<bool> Function()? onDismissProfilePhotoPrompt;

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
    this.equippedAccessories = const [],
    this.activeChallengeProgress,
    this.leaderboardHighlights = const [],
    this.leaderboardHighlightsLoading = false,
    required this.onChallengeChanged,
    this.onOpenFriendsTab,
    this.onOpenChallengesTab,
    this.onOpenLeaderboardTab,
    this.onOpenLeaderboardHighlight,
    this.onOpenProfile,
    this.onAddProfilePhoto,
    this.onDismissProfilePhotoPrompt,
  });

  @override
  Widget build(BuildContext context) {
    if (!healthAuthorized) {
      return _buildPermissionPrompt();
    }

    if (notificationsState == null) {
      return _buildNotificationPrompt();
    }

    final topInset = MediaQuery.of(context).padding.top;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final tabBarHeight = 77.5 + bottomInset;
    final bottomPadding = tabBarHeight;
    final hasProfilePhoto =
        authService.profilePhotoUrl != null &&
        authService.profilePhotoUrl!.isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(top: topInset, bottom: bottomPadding),
      child: RefreshIndicator(
        onRefresh: onRefresh,
        color: HomeColors.sageDeep,
        backgroundColor: HomeColors.surface,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.only(bottom: 24),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeroSection(context),
                    const SizedBox(height: 16),
                    _SetupPromptsSection(
                      displayName: displayName,
                      hasProfilePhoto: hasProfilePhoto,
                      authService: authService,
                      onDisplayNameChanged: onDisplayNameChanged,
                      onAddProfilePhoto: onAddProfilePhoto,
                      onDismissProfilePhotoPrompt: onDismissProfilePhotoPrompt,
                    ),
                    _buildLeaderboardHighlightsSection(),
                    if (leaderboardHighlightsLoading ||
                        leaderboardHighlights.isNotEmpty)
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

  Widget _buildHeroSection(BuildContext context) {
    if (isLoading && stepData == null) {
      return const HomePanel(
        radius: 0,
        child: SizedBox(
          height: 320,
          child: Center(
            child: SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                color: HomeColors.sageDeep,
                strokeWidth: 3,
              ),
            ),
          ),
        ),
      );
    }

    if (error != null) {
      return HomePanel(
        radius: 0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('TODAY', style: HomeText.label()),
            const SizedBox(height: 10),
            Text('Couldn’t load your pace', style: HomeText.title(size: 26)),
            const SizedBox(height: 8),
            Text(
              error!,
              style: HomeText.body(
                size: 14,
                color: HomeColors.clay,
                weight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    final steps = stepData?.steps ?? 0;
    final goal = stepGoal ?? 0;
    final progress = goal > 0 ? (steps / goal).clamp(0.0, 1.0) : 0.0;
    final stepsStr = _formatNumber(steps);
    final goalStr = goal > 0 ? _formatCompact(goal) : null;
    final remainingSteps = goal > 0 ? math.max(goal - steps, 0) : 0;
    final friendsAhead = friendsSteps.where((friend) {
      final friendSteps = friend['steps'] as int? ?? 0;
      return friendSteps > steps;
    }).length;
    final friendsOnTrack = friendsSteps.where((friend) {
      final friendGoal = friend['stepGoal'] as int?;
      return friendGoal != null && friendGoal > 0;
    }).length;
    final viewportHeight = MediaQuery.of(context).size.height;
    final trackHeight = viewportHeight < 760 ? 226.0 : 268.0;

    return HomePanel(
      padding: EdgeInsets.zero,
      radius: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: const BoxDecoration(color: HomeColors.sageDeep),
            child: CustomPaint(
              painter: const ArcadeCheckerPainter(),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      top: 0,
                      right: 0,
                      child: ProfileAvatarButton(
                        name: displayName ?? 'You',
                        imageUrl: authService.profilePhotoUrl,
                        onPressed: onOpenProfile,
                        size: 42,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 52),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Flexible(
                                  child: Text(
                                    displayName ?? 'You',
                                    textAlign: TextAlign.center,
                                    style: HomeText.title(
                                      size: 30,
                                      color: Colors.white,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                CoinBalanceBadge(
                                  coins: authService.coins,
                                  heldCoins: authService.heldCoins,
                                  coinSize: 16,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Center(
                            child: CapybaraCustomizationPreview(
                              accessories: equippedAccessories,
                              size: viewportHeight < 760 ? 104 : 122,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Steps today',
                            textAlign: TextAlign.center,
                            style: HomeText.body(
                              size: 14,
                              color: Colors.white.withValues(alpha: 0.78),
                              weight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  stepsStr,
                                  style: HomeText.display(
                                    size: 58,
                                    color: Colors.white,
                                  ),
                                ),
                                if (goalStr != null) ...[
                                  const SizedBox(width: 10),
                                  Text(
                                    'out of $goalStr',
                                    style: HomeText.body(
                                      size: 18,
                                      color: Colors.white.withValues(
                                        alpha: 0.82,
                                      ),
                                      weight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _heroSummary(
                              steps: steps,
                              goal: goal,
                              friendsAhead: friendsAhead,
                            ),
                            textAlign: TextAlign.center,
                            style: HomeText.body(
                              size: 14,
                              color: Colors.white.withValues(alpha: 0.82),
                              weight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: HomePill(
                        label: _goalMomentumLabel(
                          goal: goal,
                          remainingSteps: remainingSteps,
                          steps: steps,
                        ),
                        icon: goal > 0 && remainingSteps == 0
                            ? Icons.check_circle_rounded
                            : Icons.flag_rounded,
                        fullWidth: true,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: HomePillButton(
                        label: goal > 0 ? 'EDIT GOAL' : 'SET GOAL',
                        icon: Icons.tune_rounded,
                        onPressed: onSetStepGoal,
                      ),
                    ),
                  ],
                ),
                if (goal > 0) ...[
                  const SizedBox(height: 14),
                  _GoalProgressBar(
                    progress: progress,
                    status: remainingSteps == 0
                        ? 'Goal complete'
                        : '${_formatNumber(remainingSteps)} to go',
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Text('Step goal race', style: HomeText.title(size: 22)),
                      const Spacer(),
                      Flexible(
                        child: Text(
                          _goalTrackCaption(friendsOnTrack),
                          textAlign: TextAlign.right,
                          style: HomeText.body(
                            size: 13,
                            color: HomeColors.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  HomeCourseTrack(
                    height: trackHeight,
                    goalSteps: goal,
                    runners: [
                      GoalTrackRunner(
                        name: displayName ?? 'You',
                        progress: progress,
                        isUser: true,
                        profilePhotoUrl: authService.profilePhotoUrl,
                        accessories: equippedAccessories,
                      ),
                      for (final friend in friendsSteps)
                        GoalTrackRunner(
                          name: friend['displayName'] as String? ?? '???',
                          progress: _friendGoalProgress(friend),
                          profilePhotoUrl: friend['profilePhotoUrl'] as String?,
                          accessories:
                              (friend['accessories'] as List?)
                                  ?.cast<Map<String, dynamic>>() ??
                              const [],
                        ),
                    ],
                  ),
                ] else ...[
                  const SizedBox(height: 14),
                  HomeInsetPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Set your daily goal to unlock the live goal race and reward bonuses.',
                          style: HomeText.body(
                            size: 14,
                            color: HomeColors.muted,
                          ),
                        ),
                        const SizedBox(height: 14),
                        HomeButton(
                          label: 'SET STEP GOAL',
                          icon: Icons.flag_rounded,
                          compact: true,
                          onPressed: onSetStepGoal,
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: HomeButton(
                        label: 'CHALLENGES',
                        icon: Icons.emoji_events_rounded,
                        onPressed: () => onOpenChallengesTab?.call(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: HomeButton(
                        label: 'LEADERBOARD',
                        icon: Icons.insights_rounded,
                        isPrimary: false,
                        onPressed: () => onOpenLeaderboardTab?.call(),
                      ),
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

  Widget _buildLeaderboardHighlightsSection() {
    final cards = leaderboardHighlights.take(3).toList(growable: false);
    if (!leaderboardHighlightsLoading && cards.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Text('CLIMBING THE BOARDS', style: HomeText.label(size: 13)),
        ),
        const SizedBox(height: 10),
        if (leaderboardHighlightsLoading && cards.isEmpty)
          const _ClimbingBoardsSkeleton()
        else
          _ClimbingBoardsCarousel(
            cards: cards,
            onOpenLeaderboardHighlight: onOpenLeaderboardHighlight,
          ),
      ],
    );
  }

  Widget _buildDailyRewardSlots() {
    final steps = stepData?.steps ?? 0;
    final goal = stepGoal ?? 0;
    final hitGoal = goal > 0 && steps >= goal;
    final hitDoubleGoal = goal > 0 && steps >= goal * 2;

    return HomePanel(
      radius: 0,
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('DAILY REWARDS', style: HomeText.label(size: 13)),
          const SizedBox(height: 8),
          Text('Coin bonuses for today', style: HomeText.title(size: 26)),
          const SizedBox(height: 6),
          Text(
            'Hit your target once, then double it for the extra reward.',
            style: HomeText.body(size: 14, color: HomeColors.muted),
          ),
          const SizedBox(height: 16),
          _DailyRewardCard(
            label: '1x GOAL',
            description: 'Hit your daily step goal',
            reward: '+10 coins',
            unlocked: hitGoal,
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: HomeColors.line.withValues(alpha: 0.10)),
          const SizedBox(height: 12),
          _DailyRewardCard(
            label: '2x GOAL',
            description: 'Double your daily step goal',
            reward: '+10 coins',
            unlocked: hitDoubleGoal,
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionPrompt() {
    return _PermissionGate(
      icon: Icons.favorite_rounded,
      title: 'HEALTH DATA',
      body:
          'Bara needs access to your health data to count your daily steps.\n\n'
          "That's all we use - just your step count.",
      actionLabel: 'ENABLE HEALTH DATA',
      action: onEnableHealth,
      error: error,
      isLoading: isLoading,
    );
  }

  Widget _buildNotificationPrompt() {
    return _PermissionGate(
      icon: Icons.notifications_rounded,
      title: 'NOTIFICATIONS',
      body:
          'Get notified when a friend challenges you to a step battle!\n\n'
          'We’ll only send important updates — no spam.',
      actionLabel: 'ENABLE NOTIFICATIONS',
      action: onEnableNotifications,
    );
  }

  String _heroSummary({
    required int steps,
    required int goal,
    required int friendsAhead,
  }) {
    if (goal <= 0) {
      return 'Set a target so your pace, rewards, and races have something to chase.';
    }
    if (steps >= goal * 2) {
      return 'Double goal hit. You cleared every reward for the day.';
    }
    if (steps >= goal) {
      return 'Goal hit. Keep walking to lock in the double-goal bonus.';
    }
    if (friendsAhead > 1) {
      return '$friendsAhead friends are ahead of your pace right now.';
    }
    if (friendsAhead == 1) {
      return '1 friend is ahead of your pace right now.';
    }
    return 'Clean pace so far. You are tracking toward your target.';
  }

  String _goalMomentumLabel({
    required int goal,
    required int remainingSteps,
    required int steps,
  }) {
    if (goal <= 0) {
      return 'Set your first daily goal';
    }
    if (remainingSteps == 0) {
      if (steps >= goal * 2) return 'Double reward unlocked';
      return 'Daily goal complete';
    }
    return '${_formatNumber(remainingSteps)} steps left today';
  }

  String _goalTrackCaption(int friendsOnTrack) {
    if (friendsOnTrack == 0) {
      return 'Compare with friends\' goals';
    }
    if (friendsOnTrack == 1) {
      return 'You vs 1 friend\'s goal';
    }
    return 'You vs $friendsOnTrack friends\' goals';
  }

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
    if (n >= 1000) {
      return '${(n / 1000).toStringAsFixed(n % 1000 == 0 ? 0 : 1)}k';
    }
    return '$n';
  }
}

class _GoalProgressBar extends StatelessWidget {
  const _GoalProgressBar({required this.progress, required this.status});

  final double progress;
  final String status;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'GOAL PROGRESS',
              style: HomeText.label(color: HomeColors.muted),
            ),
            const Spacer(),
            Text(
              status,
              style: HomeText.body(size: 12, color: HomeColors.muted),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(0),
          child: Container(
            height: 14,
            color: HomeColors.surfaceMuted,
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: progress.clamp(0.0, 1.0),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: HomeColors.gold,
                    border: Border.all(
                      color: HomeColors.clay.withValues(alpha: 0.5),
                      width: 2,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PermissionGate extends StatelessWidget {
  const _PermissionGate({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.action,
    this.error,
    this.isLoading = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback action;
  final String? error;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: HomePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: HomeColors.surfaceMuted,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: HomeColors.line.withValues(alpha: 0.10),
                    ),
                  ),
                  child: Icon(icon, size: 34, color: HomeColors.sageDeep),
                ),
                const SizedBox(height: 18),
                Text(
                  title,
                  style: HomeText.label(),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  title == 'HEALTH DATA'
                      ? 'Let Bara read your daily steps'
                      : 'Stay in the loop',
                  style: HomeText.title(size: 28),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  body,
                  style: HomeText.body(size: 15, color: HomeColors.muted),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                const Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    _PermissionFeature(
                      icon: Icons.directions_walk_rounded,
                      title: 'TRACK',
                      detail: 'Daily steps',
                    ),
                    _PermissionFeature(
                      icon: Icons.emoji_events_rounded,
                      title: 'COMPETE',
                      detail: 'Friend challenges',
                    ),
                    _PermissionFeature(
                      icon: Icons.payments_rounded,
                      title: 'EARN',
                      detail: 'Goal coins',
                    ),
                  ],
                ),
                if (error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    error!,
                    style: HomeText.body(
                      size: 14,
                      color: HomeColors.clay,
                      weight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 22),
                if (isLoading)
                  const SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      color: HomeColors.sageDeep,
                      strokeWidth: 3,
                    ),
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: HomeButton(
                      label: actionLabel,
                      icon: icon,
                      onPressed: action,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PermissionFeature extends StatelessWidget {
  const _PermissionFeature({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return HomeInsetPanel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: HomeColors.sageDeep),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: HomeText.label(color: HomeColors.ink)),
              const SizedBox(height: 4),
              Text(
                detail,
                style: HomeText.body(size: 12, color: HomeColors.muted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SetupPromptsSection extends StatefulWidget {
  const _SetupPromptsSection({
    required this.displayName,
    required this.hasProfilePhoto,
    required this.authService,
    required this.onDisplayNameChanged,
    this.onAddProfilePhoto,
    this.onDismissProfilePhotoPrompt,
  });

  final String? displayName;
  final bool hasProfilePhoto;
  final AuthService authService;
  final VoidCallback onDisplayNameChanged;
  final Future<void> Function()? onAddProfilePhoto;
  final Future<bool> Function()? onDismissProfilePhotoPrompt;

  @override
  State<_SetupPromptsSection> createState() => _SetupPromptsSectionState();
}

class _SetupPromptsSectionState extends State<_SetupPromptsSection> {
  Timer? _dismissTimer;
  bool _showDismissedConfirmation = false;
  bool _isSavingDismissal = false;

  bool get _promptDismissed =>
      widget.authService.profilePhotoPromptDismissedAt != null;

  @override
  void didUpdateWidget(covariant _SetupPromptsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.displayName == null || widget.hasProfilePhoto) {
      _dismissTimer?.cancel();
      _dismissTimer = null;
      _showDismissedConfirmation = false;
      _isSavingDismissal = false;
    }
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    super.dispose();
  }

  Future<void> _openDisplayNameScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            DisplayNameScreen(authService: widget.authService),
      ),
    );
    widget.onDisplayNameChanged();
  }

  Future<void> _dismissProfilePhotoPrompt() async {
    if (_isSavingDismissal) return;

    setState(() {
      _isSavingDismissal = true;
    });

    final dismissed = await widget.onDismissProfilePhotoPrompt?.call() ?? false;
    if (!mounted) return;

    if (!dismissed) {
      setState(() {
        _isSavingDismissal = false;
      });
      return;
    }

    _dismissTimer?.cancel();
    setState(() {
      _isSavingDismissal = false;
      _showDismissedConfirmation = true;
    });

    _dismissTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() {
        _showDismissedConfirmation = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final showDisplayNamePrompt = widget.displayName == null;
    final showProfilePhotoPrompt =
        widget.displayName != null &&
        !widget.hasProfilePhoto &&
        !_showDismissedConfirmation &&
        !_promptDismissed;
    final showDismissedConfirmation =
        widget.displayName != null &&
        !widget.hasProfilePhoto &&
        _showDismissedConfirmation;

    if (!showDisplayNamePrompt &&
        !showProfilePhotoPrompt &&
        !showDismissedConfirmation) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showDisplayNamePrompt) ...[
          HomePanel(
            radius: 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SETUP', style: HomeText.label()),
                const SizedBox(height: 8),
                Text('Add your display name', style: HomeText.title(size: 24)),
                const SizedBox(height: 6),
                Text(
                  'Your friends need something better than a blank avatar to look for.',
                  style: HomeText.body(size: 14, color: HomeColors.muted),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: HomeButton(
                    label: 'SET DISPLAY NAME',
                    icon: Icons.edit_rounded,
                    onPressed: _openDisplayNameScreen,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (showProfilePhotoPrompt) ...[
          HomePanel(
            radius: 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('PROFILE', style: HomeText.label()),
                const SizedBox(height: 8),
                Text('ADD A PROFILE PHOTO?', style: HomeText.title(size: 24)),
                const SizedBox(height: 6),
                Text(
                  'Make it easier for friends to spot you in races, challenges, and leaderboards.',
                  style: HomeText.body(size: 14, color: HomeColors.muted),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: HomeButton(
                        label: 'ADD PHOTO',
                        icon: Icons.add_a_photo_rounded,
                        onPressed: _isSavingDismissal
                            ? null
                            : () => widget.onAddProfilePhoto?.call(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: HomeButton(
                        label: 'NO THANKS',
                        icon: Icons.close_rounded,
                        isPrimary: false,
                        onPressed: _dismissProfilePhotoPrompt,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (showDismissedConfirmation)
          HomePanel(
            key: const Key('profile-photo-dismissed-confirmation'),
            radius: 0,
            child: Text(
              'You can add one anytime in Profile.',
              style: HomeText.body(size: 14, color: HomeColors.muted),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}

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
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: unlocked ? HomeColors.cream : HomeColors.surfaceMuted,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: unlocked
                  ? HomeColors.gold.withValues(alpha: 0.55)
                  : HomeColors.line.withValues(alpha: 0.10),
              width: 2,
            ),
          ),
          child: Center(
            child: unlocked
                ? const SpinningCoin(size: 24)
                : Icon(
                    Icons.lock_rounded,
                    size: 22,
                    color: HomeColors.muted.withValues(alpha: 0.65),
                  ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: HomeText.title(
                  size: 17,
                  color: unlocked ? HomeColors.ink : HomeColors.muted,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: HomeText.body(
                  size: 13,
                  color: unlocked ? HomeColors.muted : HomeColors.muted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          reward,
          style: HomeText.title(
            size: 16,
            color: unlocked ? HomeColors.success : HomeColors.muted,
          ),
        ),
      ],
    );
  }
}

class _ClimbingBoardsSkeleton extends StatelessWidget {
  const _ClimbingBoardsSkeleton();

  @override
  Widget build(BuildContext context) {
    return HomePanel(
      key: const Key('climbing-boards-skeleton'),
      padding: EdgeInsets.zero,
      backgroundColor: HomeColors.sageDeep,
      borderColor: HomeColors.lineSoft,
      radius: 0,
      child: Container(
        height: 170,
        decoration: const BoxDecoration(color: HomeColors.sageDeep),
        child: CustomPaint(
          painter: const ArcadeCheckerPainter(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                _SkeletonBar(width: 132, height: 28),
                SizedBox(height: 18),
                _SkeletonBar(width: 228, height: 24),
                SizedBox(height: 10),
                _SkeletonBar(width: 176, height: 16),
                Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _SkeletonDot(active: true),
                    SizedBox(width: 6),
                    _SkeletonDot(),
                    SizedBox(width: 6),
                    _SkeletonDot(),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ClimbingBoardsCarousel extends StatefulWidget {
  const _ClimbingBoardsCarousel({
    required this.cards,
    this.onOpenLeaderboardHighlight,
  });

  final List<Map<String, dynamic>> cards;
  final void Function(String leaderboardType, String period)?
  onOpenLeaderboardHighlight;

  @override
  State<_ClimbingBoardsCarousel> createState() =>
      _ClimbingBoardsCarouselState();
}

class _ClimbingBoardsCarouselState extends State<_ClimbingBoardsCarousel> {
  late final PageController _pageController;
  Timer? _autoAdvanceTimer;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _restartAutoAdvance();
  }

  @override
  void didUpdateWidget(covariant _ClimbingBoardsCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cards.length != widget.cards.length) {
      if (_currentPage >= widget.cards.length) {
        _currentPage = 0;
        if (_pageController.hasClients) {
          _pageController.jumpToPage(0);
        }
      }
      _restartAutoAdvance();
    }
  }

  @override
  void dispose() {
    _autoAdvanceTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _restartAutoAdvance() {
    _autoAdvanceTimer?.cancel();
    if (widget.cards.length < 2) return;

    _autoAdvanceTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!_pageController.hasClients || widget.cards.length < 2) return;
      final nextPage = (_currentPage + 1) % widget.cards.length;
      _pageController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _stopAutoAdvance() {
    _autoAdvanceTimer?.cancel();
    _autoAdvanceTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    return HomePanel(
      padding: EdgeInsets.zero,
      backgroundColor: HomeColors.sageDeep,
      borderColor: HomeColors.lineSoft,
      radius: 0,
      child: SizedBox(
        height: 170,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(0),
          child: Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(
                  color: HomeColors.sageDeep,
                  child: CustomPaint(painter: const ArcadeCheckerPainter()),
                ),
              ),
              NotificationListener<ScrollStartNotification>(
                onNotification: (_) {
                  _stopAutoAdvance();
                  return false;
                },
                child: NotificationListener<ScrollEndNotification>(
                  onNotification: (_) {
                    _restartAutoAdvance();
                    return false;
                  },
                  child: PageView.builder(
                    key: const Key('climbing-boards-page-view'),
                    controller: _pageController,
                    itemCount: widget.cards.length,
                    onPageChanged: (page) {
                      setState(() => _currentPage = page);
                    },
                    itemBuilder: (context, index) {
                      final card = widget.cards[index];
                      final title = card['title'] as String? ?? '';
                      final subtitle = card['subtitle'] as String? ?? '';
                      final leaderboardType =
                          card['leaderboardType'] as String? ?? 'steps';
                      final period = card['period'] as String? ?? 'today';

                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            _stopAutoAdvance();
                            widget.onOpenLeaderboardHighlight?.call(
                              leaderboardType,
                              period,
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _ClimbingBoardsBadge(
                                  label: _badgeLabel(leaderboardType, period),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: HomeText.title(
                                    size: 22,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  subtitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: HomeText.body(
                                    size: 14,
                                    color: Colors.white.withValues(alpha: 0.78),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 12,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (int i = 0; i < widget.cards.length; i++) ...[
                      if (i > 0) const SizedBox(width: 6),
                      _ClimbingBoardsDot(active: i == _currentPage),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _badgeLabel(String leaderboardType, String period) {
    final typeLabel = switch (leaderboardType) {
      'challenges' => 'CHALLENGES',
      'races' => 'RACES',
      _ => 'STEPS',
    };
    final periodLabel = switch (period) {
      'allTime' => 'ALL TIME',
      'month' => 'MONTH',
      'week' => 'WEEK',
      _ => 'TODAY',
    };
    return '$typeLabel  •  $periodLabel';
  }
}

class _ClimbingBoardsBadge extends StatelessWidget {
  const _ClimbingBoardsBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return HomePill(
      label: label,
      backgroundColor: HomeColors.gold,
      foregroundColor: HomeColors.ink,
    );
  }
}

class _ClimbingBoardsDot extends StatelessWidget {
  const _ClimbingBoardsDot({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: active ? 18 : 8,
      height: 8,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: active ? HomeColors.gold : Colors.white.withValues(alpha: 0.28),
      ),
    );
  }
}

class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _SkeletonDot extends StatelessWidget {
  const _SkeletonDot({this.active = false});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: active ? 18 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: active
            ? HomeColors.gold.withValues(alpha: 0.85)
            : Colors.white.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}
