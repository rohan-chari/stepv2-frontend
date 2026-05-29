import 'package:flutter/material.dart';

import '../styles.dart';
import '../widgets/app_avatar.dart';
import '../widgets/arcade_page.dart';
import '../widgets/coin_balance_badge.dart';
import '../widgets/game_container.dart';
import '../widgets/goal_track.dart';
import '../widgets/home_chrome.dart';
import '../widgets/home_course_track.dart';
import '../widgets/info_board_card.dart';
import '../widgets/pill_button.dart';
import '../widgets/wooden_tab_bar.dart';
import 'tutorial_screen.dart';

class TutorialMockHost extends StatelessWidget {
  const TutorialMockHost({super.key, required this.page, required this.keys});

  final TutorialMockPage page;
  final Map<String, GlobalKey> keys;

  @override
  Widget build(BuildContext context) {
    final tabIndex = switch (page) {
      TutorialMockPage.home => 0,
      TutorialMockPage.races => 1,
      TutorialMockPage.leaderboard => 3,
      TutorialMockPage.friends => null,
    };

    return Stack(
      children: [
        const Positioned.fill(child: ArcadePageBackground(showHeader: false)),
        Positioned.fill(
          child: Padding(
            padding: EdgeInsets.only(bottom: tabIndex == null ? 0 : 78),
            child: switch (page) {
              TutorialMockPage.home => _MockHome(keys: keys),
              TutorialMockPage.races => _MockRaces(keys: keys),
              TutorialMockPage.leaderboard => _MockLeaderboard(keys: keys),
              TutorialMockPage.friends => _MockFriends(keys: keys),
            },
          ),
        ),
        if (tabIndex != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AbsorbPointer(
              child: WoodenTabBar(
                currentIndex: tabIndex,
                onTap: (_) {},
                items: const [
                  WoodenTabItem(icon: Icons.home_rounded, label: 'Home'),
                  WoodenTabItem(
                    icon: Icons.directions_run_rounded,
                    label: 'Races',
                  ),
                  WoodenTabItem(
                    icon: Icons.leaderboard_rounded,
                    label: 'Leaderboard',
                  ),
                  WoodenTabItem(icon: Icons.person_rounded, label: 'Profile'),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _MockHome extends StatelessWidget {
  const _MockHome({required this.keys});

  final Map<String, GlobalKey> keys;

  @override
  Widget build(BuildContext context) {
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final compact = viewportHeight < 760;

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HomePanel(
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
                      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          const Positioned(
                            top: 0,
                            right: 0,
                            child: ProfileAvatarButton(name: 'Rohan', size: 42),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 52,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        'Rohan',
                                        textAlign: TextAlign.center,
                                        overflow: TextOverflow.ellipsis,
                                        style: HomeText.title(
                                          size: 30,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    CoinBalanceBadge(
                                      key: keys['home.coins'],
                                      coins: 1840,
                                      coinSize: 16,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              Center(
                                child: CapybaraCustomizationPreview(
                                  accessories: _sampleAccessories,
                                  size: compact ? 92 : 110,
                                ),
                              ),
                              const SizedBox(height: 4),
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
                              KeyedSubtree(
                                key: keys['home.steps'],
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.baseline,
                                    textBaseline: TextBaseline.alphabetic,
                                    children: [
                                      Text(
                                        '13,420',
                                        style: HomeText.display(
                                          size: compact ? 50 : 58,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        'out of 15k',
                                        style: HomeText.body(
                                          size: 18,
                                          color: Colors.white.withValues(
                                            alpha: 0.82,
                                          ),
                                          weight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '1,580 steps left to keep your streak moving.',
                                textAlign: TextAlign.center,
                                style: HomeText.body(
                                  size: 14,
                                  color: Colors.white.withValues(alpha: 0.82),
                                  weight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: HomePill(
                              label: '1,580 TO GO',
                              icon: Icons.flag_rounded,
                              fullWidth: true,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: HomePillButton(
                              key: keys['home.goal'],
                              label: 'EDIT GOAL',
                              icon: Icons.tune_rounded,
                              onPressed: () {},
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const _MockDailyReward(),
                      const SizedBox(height: 10),
                      HomePillButton(
                        label: 'HOW TO PLAY',
                        icon: Icons.help_outline_rounded,
                        onPressed: () {},
                      ),
                      const SizedBox(height: 14),
                      const _MockGoalProgressBar(
                        progress: 0.89,
                        status: 'Almost there',
                      ),
                      if (!compact) ...[
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Text(
                              'Step goal race',
                              style: HomeText.title(size: 22),
                            ),
                            const Spacer(),
                            Flexible(
                              child: Text(
                                '3 friends on track',
                                textAlign: TextAlign.right,
                                style: HomeText.body(
                                  size: 13,
                                  color: HomeColors.muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        HomeCourseTrack(
                          height: 176,
                          goalSteps: 15000,
                          runners: const [
                            GoalTrackRunner(
                              name: 'Rohan',
                              progress: 0.89,
                              isUser: true,
                              accessories: _sampleAccessories,
                            ),
                            GoalTrackRunner(name: 'Maya', progress: 0.74),
                            GoalTrackRunner(name: 'Sam', progress: 0.62),
                            GoalTrackRunner(name: 'Jordan', progress: 0.96),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MockRaces extends StatelessWidget {
  const _MockRaces({required this.keys});

  final Map<String, GlobalKey> keys;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: Column(
        children: [
          const _MockStatusBar(),
          const SizedBox(height: 16),
          InfoBoardCard(
            badgeLabel: 'RACES',
            title: 'First to the finish line wins.',
            subtitle:
                'Set a step target, invite friends, and race for the pot.',
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            borderRadius: 0,
            children: [
              const SizedBox(height: 14),
              PillButton(
                label: 'NEW RACE',
                variant: PillButtonVariant.secondary,
                fontSize: 14,
                fullWidth: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                onPressed: () {},
              ),
              const SizedBox(height: 8),
              PillButton(
                label: 'BROWSE PUBLIC RACES',
                variant: PillButtonVariant.secondary,
                fontSize: 14,
                fullWidth: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                onPressed: () {},
              ),
            ],
          ),
          const SizedBox(height: 16),
          const _MockSectionHeader(title: 'ACTIVE RACES', count: 2),
          const SizedBox(height: 8),
          GameContainer(
            key: keys['races.card'],
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
            child: Column(
              children: [
                _MockRaceRow(
                  name: 'Weekend 10K',
                  meta: '30k steps - 6 runners',
                  status: 'ACTIVE',
                  placement: '2ND',
                  queuedBoxKey: keys['races.box'],
                  queuedBoxes: 1,
                  odd: false,
                ),
                _MockDivider(),
                const _MockRaceRow(
                  name: 'Lunch Loop',
                  meta: '18k steps - 4 runners',
                  status: 'ACTIVE',
                  placement: '4TH',
                  queuedBoxes: 0,
                  odd: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const _MockSectionHeader(title: 'WAITING TO START', count: 1),
          const SizedBox(height: 8),
          const GameContainer(
            padding: EdgeInsets.symmetric(vertical: 6, horizontal: 0),
            child: _MockRaceRow(
              name: 'Morning Crew',
              meta: '12k steps - starts when Alex joins',
              status: 'SETUP',
              queuedBoxes: 0,
              odd: false,
            ),
          ),
        ],
      ),
    );
  }
}

class _MockLeaderboard extends StatelessWidget {
  const _MockLeaderboard({required this.keys});

  final Map<String, GlobalKey> keys;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: Column(
        children: [
          const _MockStatusBar(),
          const SizedBox(height: 12),
          InfoBoardCard(
            badgeLabel: 'RANKING',
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            borderRadius: 0,
            children: [
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: PillButton(
                      label: 'STEPS',
                      onPressed: () {},
                      variant: PillButtonVariant.secondary,
                      fontSize: 11,
                      fullWidth: true,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 10,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: PillButton(
                      label: 'CHALLENGES',
                      onPressed: () {},
                      variant: PillButtonVariant.accent,
                      fontSize: 11,
                      fullWidth: true,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 10,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: PillButton(
                      label: 'RACES',
                      onPressed: () {},
                      variant: PillButtonVariant.accent,
                      fontSize: 11,
                      fullWidth: true,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 10,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const _MockFilter(label: 'THIS WEEK'),
            ],
          ),
          const SizedBox(height: 16),
          GameContainer(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  child: Row(
                    children: [
                      SizedBox(width: 36, child: _TableHeader('#')),
                      SizedBox(width: 8),
                      Expanded(child: _TableHeader('PLAYER')),
                      SizedBox(
                        width: 74,
                        child: _TableHeader('STEPS', alignRight: true),
                      ),
                    ],
                  ),
                ),
                _MockDivider(),
                const _MockLeaderboardRow(
                  rank: '1st',
                  name: 'Sam Rivera',
                  value: '98.4k',
                  odd: false,
                ),
                const _MockLeaderboardRow(
                  rank: '2nd',
                  name: 'Maya Chen',
                  value: '84.2k',
                  odd: true,
                ),
                _MockLeaderboardRow(
                  key: keys['leaderboard.rank'],
                  rank: '3rd',
                  name: 'Rohan',
                  value: '72.1k',
                  isYou: true,
                  odd: false,
                ),
                const _MockLeaderboardRow(
                  rank: '4',
                  name: 'Jordan Lee',
                  value: '64.8k',
                  odd: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MockFriends extends StatelessWidget {
  const _MockFriends({required this.keys});

  final Map<String, GlobalKey> keys;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        children: [
          const _MockStatusBar(showBack: true),
          const SizedBox(height: 12),
          const InfoBoardCard(
            badgeLabel: 'YOUR FRIENDS',
            title: 'Tap a friend for options.',
            subtitle: '4 adventurers in your crew',
            padding: EdgeInsets.fromLTRB(16, 12, 16, 14),
            borderRadius: 0,
          ),
          const SizedBox(height: 12),
          KeyedSubtree(
            key: keys['friends.search'],
            child: const _MockSearchField(),
          ),
          const SizedBox(height: 16),
          const _MockSectionHeader(title: 'SENT REQUESTS', count: 1),
          const SizedBox(height: 8),
          const GameContainer(
            padding: EdgeInsets.symmetric(vertical: 6, horizontal: 0),
            child: _MockPendingFriendRow(name: 'Priya N.', odd: false),
          ),
          const SizedBox(height: 16),
          const _MockSectionHeader(title: 'FRIENDS', count: 4),
          const SizedBox(height: 8),
          const GameContainer(
            padding: EdgeInsets.symmetric(vertical: 6, horizontal: 0),
            child: Column(
              children: [
                _MockFriendRow(name: 'Maya Chen', steps: '12.8k', odd: false),
                _MockDivider(),
                _MockFriendRow(name: 'Sam Rivera', steps: '10.4k', odd: true),
                _MockDivider(),
                _MockFriendRow(name: 'Jordan Lee', steps: '8.9k', odd: false),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MockStatusBar extends StatelessWidget {
  const _MockStatusBar({this.showBack = false});

  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (showBack) ...[
          const Padding(
            padding: EdgeInsets.all(8),
            child: Icon(Icons.arrow_back, color: AppColors.textDark, size: 24),
          ),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      'Rohan',
                      style: PixelText.title(
                        size: 26,
                        color: AppColors.textDark,
                      ).copyWith(shadows: _textShadows),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const CoinBalanceBadge(coins: 1840),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '13,420 / 15k',
                style: PixelText.number(
                  size: 20,
                  color: AppColors.accent,
                ).copyWith(shadows: _textShadows),
              ),
            ],
          ),
        ),
        const ProfileAvatarButton(name: 'Rohan'),
      ],
    );
  }
}

class _MockDailyReward extends StatelessWidget {
  const _MockDailyReward();

  @override
  Widget build(BuildContext context) {
    return HomeInsetPanel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      backgroundColor: HomeColors.cream,
      borderColor: HomeColors.gold,
      child: Row(
        children: [
          const Icon(Icons.monetization_on_rounded, color: HomeColors.ink),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Daily reward',
                  style: HomeText.body(
                    size: 14,
                    color: HomeColors.ink,
                    weight: FontWeight.w800,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Ready to open',
                  style: HomeText.body(
                    size: 12,
                    color: HomeColors.muted,
                    weight: FontWeight.w700,
                    height: 1.0,
                  ),
                ),
              ],
            ),
          ),
          const HomePill(
            label: 'CLAIM',
            backgroundColor: HomeColors.ink,
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          ),
        ],
      ),
    );
  }
}

class _MockGoalProgressBar extends StatelessWidget {
  const _MockGoalProgressBar({required this.progress, required this.status});

  final double progress;
  final String status;

  @override
  Widget build(BuildContext context) {
    return HomeInsetPanel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Goal progress', style: HomeText.label()),
              const Spacer(),
              Text(status, style: HomeText.label(color: HomeColors.sageDeep)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 12,
              backgroundColor: HomeColors.surface,
              valueColor: const AlwaysStoppedAnimation(HomeColors.sage),
            ),
          ),
        ],
      ),
    );
  }
}

class _MockSectionHeader extends StatelessWidget {
  const _MockSectionHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: PixelText.title(
            size: 18,
            color: AppColors.textMid,
          ).copyWith(shadows: _textShadows),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.textMid.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: PixelText.title(size: 12, color: AppColors.textMid),
          ),
        ),
        const Spacer(),
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: AppColors.parchmentLight,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.parchmentBorder, width: 1.2),
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.remove_rounded,
            size: 18,
            color: AppColors.textMid,
          ),
        ),
      ],
    );
  }
}

class _MockRaceRow extends StatelessWidget {
  const _MockRaceRow({
    required this.name,
    required this.meta,
    required this.status,
    required this.queuedBoxes,
    required this.odd,
    this.placement,
    this.queuedBoxKey,
  });

  final String name;
  final String meta;
  final String status;
  final int queuedBoxes;
  final bool odd;
  final String? placement;
  final Key? queuedBoxKey;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (status) {
      'ACTIVE' => AppColors.pillGreenDark,
      'SETUP' => AppColors.pillGoldDark,
      _ => AppColors.textMid,
    };

    return Container(
      color: odd
          ? AppColors.parchmentDark.withValues(alpha: 0.25)
          : Colors.transparent,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: PixelText.title(
                          size: 18,
                          color: AppColors.textDark,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    if (placement != null) ...[
                      const SizedBox(width: 8),
                      _MockMetaChip(
                        label: placement!,
                        backgroundColor: AppColors.pillGreenDark.withValues(
                          alpha: 0.16,
                        ),
                        textColor: AppColors.pillGreenDark,
                      ),
                    ],
                    if (queuedBoxes > 0) ...[
                      const SizedBox(width: 6),
                      _MockMetaChip(
                        key: queuedBoxKey,
                        label: '$queuedBoxes QUEUED',
                        backgroundColor: AppColors.coinLight.withValues(
                          alpha: 0.18,
                        ),
                        textColor: AppColors.coinDark,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  meta,
                  style: PixelText.body(size: 14, color: AppColors.textMid),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: statusColor,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              status,
              style: PixelText.title(size: 13, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _MockMetaChip extends StatelessWidget {
  const _MockMetaChip({
    super.key,
    required this.label,
    required this.backgroundColor,
    required this.textColor,
  });

  final String label;
  final Color backgroundColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: PixelText.title(size: 11, color: textColor)),
    );
  }
}

class _MockFilter extends StatelessWidget {
  const _MockFilter({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.parchmentLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.parchmentBorder, width: 1.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: PixelText.title(size: 13, color: AppColors.textDark),
            ),
          ),
          const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: AppColors.textMid,
          ),
        ],
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader(this.label, {this.alignRight = false});

  final String label;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: PixelText.title(size: 15, color: AppColors.textMid),
      textAlign: alignRight ? TextAlign.right : TextAlign.left,
    );
  }
}

class _MockLeaderboardRow extends StatelessWidget {
  const _MockLeaderboardRow({
    super.key,
    required this.rank,
    required this.name,
    required this.value,
    required this.odd,
    this.isYou = false,
  });

  final String rank;
  final String name;
  final String value;
  final bool odd;
  final bool isYou;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: isYou
          ? AppColors.accent.withValues(alpha: 0.12)
          : odd
          ? AppColors.parchmentDark.withValues(alpha: 0.3)
          : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              rank,
              style: PixelText.title(
                size: rank.length > 1 ? 13 : 16,
                color:
                    rank.endsWith('st') ||
                        rank.endsWith('nd') ||
                        rank.endsWith('rd')
                    ? AppColors.coinMid
                    : AppColors.textDark,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 8),
          AppAvatar(
            name: name,
            size: 32,
            isUser: isYou,
            borderColor: isYou ? AppColors.accent : Colors.white,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              style: PixelText.body(
                size: 16,
                color: isYou ? AppColors.accent : AppColors.textDark,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 74,
            child: Text(
              value,
              style: PixelText.title(
                size: 16,
                color: isYou ? AppColors.accent : AppColors.textDark,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class _MockSearchField extends StatelessWidget {
  const _MockSearchField();

  @override
  Widget build(BuildContext context) {
    return TextField(
      enabled: false,
      textAlign: TextAlign.center,
      style: PixelText.body(size: 16, color: AppColors.textDark),
      decoration: InputDecoration(
        filled: true,
        fillColor: AppColors.parchmentLight,
        hintText: 'Search by display name',
        hintStyle: PixelText.body(size: 16, color: AppColors.parchmentBorder),
        prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textMid),
        disabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: AppColors.parchmentBorder),
          borderRadius: BorderRadius.circular(8),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
    );
  }
}

class _MockFriendRow extends StatelessWidget {
  const _MockFriendRow({
    required this.name,
    required this.steps,
    required this.odd,
  });

  final String name;
  final String steps;
  final bool odd;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: odd
          ? AppColors.parchmentDark.withValues(alpha: 0.25)
          : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          AppAvatar(name: name, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              style: PixelText.body(size: 16, color: AppColors.textDark),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            steps,
            style: PixelText.title(size: 12, color: AppColors.textMid),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.more_horiz, size: 22, color: AppColors.textMid),
        ],
      ),
    );
  }
}

class _MockPendingFriendRow extends StatelessWidget {
  const _MockPendingFriendRow({required this.name, required this.odd});

  final String name;
  final bool odd;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: odd
          ? AppColors.parchmentDark.withValues(alpha: 0.25)
          : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          AppAvatar(name: name, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              style: PixelText.body(size: 16, color: AppColors.textDark),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              'PENDING',
              style: PixelText.title(size: 11, color: AppColors.textMid),
            ),
          ),
          const PillButton(
            label: 'CANCEL',
            variant: PillButtonVariant.accent,
            fontSize: 11,
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            onPressed: null,
          ),
        ],
      ),
    );
  }
}

class _MockDivider extends StatelessWidget {
  const _MockDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 14),
      color: AppColors.parchmentBorder.withValues(alpha: 0.45),
    );
  }
}

const _textShadows = [
  Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
];

const List<Map<String, dynamic>> _sampleAccessories = [
  {
    'slot': 'HEAD',
    'assetKey': 'baseball_cap',
    'renderMetadata': {'offsetX': -0.01, 'offsetY': 0.02, 'rotation': -0.08},
  },
  {
    'slot': 'FACE',
    'assetKey': 'sunglasses',
    'renderMetadata': {
      'offsetX': 0.025,
      'offsetY': -0.04,
      'rotation': -0.08,
      'scale': 1.65,
    },
  },
  {
    'slot': 'FEET',
    'assetKey': 'shoes',
    'renderMetadata': {
      'offsetX': 0.03,
      'offsetY': 0.02,
      'rotation': -0.03,
      'scale': 1.1,
    },
  },
];
