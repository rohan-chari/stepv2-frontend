import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/step_data.dart';
import '../../services/auth_service.dart';
import '../../styles.dart';
import '../../widgets/feature_highlights_row.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/pill_icon_button.dart';
import '../../widgets/coin_balance_badge.dart';
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
  final List<Map<String, dynamic>> leaderboardHighlights;
  final bool leaderboardHighlightsLoading;
  final VoidCallback onChallengeChanged;
  final VoidCallback? onOpenFriendsTab;
  final VoidCallback? onOpenChallengesTab;
  final VoidCallback? onOpenLeaderboardTab;
  final void Function(String leaderboardType, String period)?
  onOpenLeaderboardHighlight;
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
    this.leaderboardHighlights = const [],
    this.leaderboardHighlightsLoading = false,
    required this.onChallengeChanged,
    this.onOpenFriendsTab,
    this.onOpenChallengesTab,
    this.onOpenLeaderboardTab,
    this.onOpenLeaderboardHighlight,
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

                    _buildGoalTrackSection(context),
                    const SizedBox(height: 16),

                    _buildLeaderboardHighlightsSection(),
                    if (leaderboardHighlightsLoading ||
                        leaderboardHighlights.isNotEmpty)
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

  Widget _buildLeaderboardHighlightsSection() {
    final cards = leaderboardHighlights.take(3).toList(growable: false);
    if (!leaderboardHighlightsLoading && cards.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'CLIMBING THE BOARDS',
          style: PixelText.title(
            size: 18,
            color: AppColors.textMid,
          ).copyWith(shadows: _textShadows),
        ),
        const SizedBox(height: 8),
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
                  CoinBalanceBadge(
                    coins: authService.coins,
                    heldCoins: authService.heldCoins,
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

  Widget _buildGoalTrackSection(BuildContext context) {
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
    final viewportHeight = MediaQuery.of(context).size.height;
    final trackHeight = viewportHeight < 760 ? 236.0 : 300.0;

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
        height: trackHeight,
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
    if (n >= 1000) {
      return '${(n / 1000).toStringAsFixed(n % 1000 == 0 ? 0 : 1)}k';
    }
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

class _ClimbingBoardsSkeleton extends StatelessWidget {
  const _ClimbingBoardsSkeleton();

  @override
  Widget build(BuildContext context) {
    return GameContainer(
      key: const Key('climbing-boards-skeleton'),
      padding: const EdgeInsets.all(0),
      child: Container(
        height: 146,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.pillGreen, AppColors.pillGreenDark],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SkeletonBar(width: 126, height: 18),
              const SizedBox(height: 16),
              _SkeletonBar(width: 240, height: 20),
              const SizedBox(height: 10),
              _SkeletonBar(width: 190, height: 14),
              const Spacer(),
              Align(
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    _SkeletonDot(active: true),
                    SizedBox(width: 6),
                    _SkeletonDot(),
                    SizedBox(width: 6),
                    _SkeletonDot(),
                  ],
                ),
              ),
            ],
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
    return GameContainer(
      padding: const EdgeInsets.all(0),
      child: SizedBox(
        height: 146,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.pillGreen, AppColors.pillGreenDark],
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              children: [
                NotificationListener<ScrollStartNotification>(
                  onNotification: (_) {
                    _stopAutoAdvance();
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

                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          _stopAutoAdvance();
                          widget.onOpenLeaderboardHighlight?.call(
                            leaderboardType,
                            period,
                          );
                        },
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            gradient: const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                AppColors.pillGreen,
                                AppColors.pillGreenDark,
                              ],
                            ),
                          ),
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Colors.white.withValues(alpha: 0.10),
                                        Colors.transparent,
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  14,
                                  10,
                                  14,
                                  16,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _ClimbingBoardsBadge(
                                      label: _badgeLabel(
                                        leaderboardType,
                                        period,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            title,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style:
                                                PixelText.title(
                                                  size: 16,
                                                  color:
                                                      AppColors.parchmentLight,
                                                ).copyWith(
                                                  shadows: HomeTab._textShadows,
                                                ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            subtitle,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style:
                                                PixelText.body(
                                                  size: 12.5,
                                                  color: AppColors.parchment,
                                                ).copyWith(
                                                  shadows: HomeTab._textShadows,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 10,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.pillGold, AppColors.pillGoldDark],
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.pillGoldShadow, width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: AppColors.pillGoldShadow,
            offset: Offset(0, 2),
            blurRadius: 0,
          ),
        ],
      ),
      child: Text(
        label,
        style: PixelText.pill(size: 10, color: AppColors.textDark),
      ),
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
        color: active ? AppColors.pillGold : AppColors.parchmentDark,
        border: Border.all(
          color: active ? AppColors.pillGoldShadow : AppColors.parchmentBorder,
        ),
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
        color: Colors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(10),
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
            ? AppColors.pillGold.withValues(alpha: 0.85)
            : Colors.white.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}
