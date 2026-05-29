import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/loadable.dart';
import '../../styles.dart';
import '../../models/step_data.dart';
import '../../services/auth_service.dart';
import '../../services/backend_api_service.dart';
import '../../widgets/coin_balance_badge.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/step_milestones_section.dart';
import '../../widgets/streak_chip.dart' show StreakChip, StreakChipState;
import '../../widgets/active_race_card.dart';
import '../../widgets/home_chrome.dart';
import '../../widgets/home_course_track.dart' show CapybaraCustomizationPreview;
import '../../widgets/loading_skeleton.dart';
import '../../widgets/race_opportunity_card.dart';
import '../display_name_screen.dart';
import '../public_races_screen.dart';

class HomeTab extends StatelessWidget {
  final StepData? stepData;
  final bool isLoading;
  final String? error;
  final bool healthAuthorized;
  final bool? notificationsState;
  final String? displayName;
  final AuthService authService;
  final BackendApiService backendApiService;
  final Future<void> Function() onRefresh;
  final VoidCallback onEnableHealth;
  final VoidCallback onEnableNotifications;
  final VoidCallback onDisplayNameChanged;
  final List<Map<String, dynamic>> friendsSteps;
  final Loadable<List<Map<String, dynamic>>>? friendsStepsState;
  final List<Map<String, dynamic>> equippedAccessories;
  final Loadable<Map<String, dynamic>>? shopCatalogState;
  final List<Map<String, dynamic>> leaderboardHighlights;
  final Loadable<List<Map<String, dynamic>>>? leaderboardHighlightsState;
  final bool leaderboardHighlightsLoading;
  final VoidCallback? onOpenFriendsTab;
  final VoidCallback? onOpenLeaderboardTab;
  final void Function(String leaderboardType, String period)?
  onOpenLeaderboardHighlight;
  final VoidCallback? onOpenShop;
  final Future<void> Function()? onAddProfilePhoto;
  final Future<bool> Function()? onDismissProfilePhotoPrompt;
  final Map<String, dynamic>? raceCard;
  final GlobalKey<StreakChipState>? streakChipKey;
  final GlobalKey<StepMilestonesSectionState>? stepMilestonesKey;
  final void Function(String raceId)? onOpenRace;
  final Future<void> Function(String raceId)? onJoinRaceFromCard;
  final Future<void> Function(String raceId)? onAcceptRaceInvite;
  final Future<void> Function(String raceId)? onDeclineRaceInvite;
  final void Function(String friendUserId)? onChallengeFriendBack;

  const HomeTab({
    super.key,
    required this.stepData,
    required this.isLoading,
    required this.error,
    required this.healthAuthorized,
    required this.notificationsState,
    required this.displayName,
    required this.authService,
    required this.backendApiService,
    required this.onRefresh,
    required this.onEnableHealth,
    required this.onEnableNotifications,
    required this.onDisplayNameChanged,
    required this.friendsSteps,
    this.friendsStepsState,
    this.equippedAccessories = const [],
    this.shopCatalogState,
    this.leaderboardHighlights = const [],
    this.leaderboardHighlightsState,
    this.leaderboardHighlightsLoading = false,
    this.onOpenFriendsTab,
    this.onOpenLeaderboardTab,
    this.onOpenLeaderboardHighlight,
    this.onOpenShop,
    this.onAddProfilePhoto,
    this.onDismissProfilePhotoPrompt,
    this.raceCard,
    this.streakChipKey,
    this.stepMilestonesKey,
    this.onOpenRace,
    this.onJoinRaceFromCard,
    this.onAcceptRaceInvite,
    this.onDeclineRaceInvite,
    this.onChallengeFriendBack,
  });

  @override
  Widget build(BuildContext context) {
    // Onboarding (health + notification permission gates) is now rendered by
    // OnboardingFlow in main_shell; HomeTab is only built once onboarding is
    // complete, so it always renders the real home below.
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
        color: AppColors.accent,
        backgroundColor: AppColors.parchment,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _buildHeroSection(context)),
            SliverToBoxAdapter(
              child: ColoredBox(
                color: AppColors.parchment,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (raceCard != null) _buildRaceSection(),
                      _SetupPromptsSection(
                        displayName: displayName,
                        hasProfilePhoto: hasProfilePhoto,
                        authService: authService,
                        onDisplayNameChanged: onDisplayNameChanged,
                        onAddProfilePhoto: onAddProfilePhoto,
                        onDismissProfilePhotoPrompt:
                            onDismissProfilePhotoPrompt,
                      ),
                      _buildLeaderboardHighlightsSection(),
                      const _HomeSectionHeader(title: 'STEP MILESTONES'),
                      StepMilestonesSection(
                        key: stepMilestonesKey,
                        authService: authService,
                        backendApiService: backendApiService,
                        currentSteps: stepData?.steps,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// RACES section on home — its own green-checkered surface (matches the
  /// original home palette) holding the section header + active-races
  /// carousel OR the RaceOpportunityCard for non-active states.
  Widget _buildRaceSection() {
    final card = raceCard!;
    return DecoratedBox(
      decoration: const BoxDecoration(color: HomeColors.sageDeep),
      child: CustomPaint(
        painter: const ArcadeCheckerPainter(drawBottomStripe: false),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _HomeSectionHeader(title: 'RACES', onDark: true),
            if (card['state'] == 'ACTIVE_RACES')
              _buildActiveRacesRow(card)
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                child: RaceOpportunityCard(
                  data: RaceCardData.fromJson(card),
                  onAccept: onAcceptRaceInvite == null
                      ? null
                      : (raceId) => onAcceptRaceInvite!(raceId),
                  onDecline: onDeclineRaceInvite == null
                      ? null
                      : (raceId) => onDeclineRaceInvite!(raceId),
                  onOpenRace: onOpenRace,
                  onJoinRace: onJoinRaceFromCard == null
                      ? null
                      : (raceId) => onJoinRaceFromCard!(raceId),
                  onChallengeBack: onChallengeFriendBack,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Horizontally-scrollable row of [ActiveRaceCard]s, one per active race the
  /// user is in. Driven by the opt-in `ACTIVE_RACES` backend state. Reads the
  /// response defensively (missing/null fields default safely) so a backend on
  /// a different version can't crash the row.
  Widget _buildActiveRacesRow(Map<String, dynamic> cardData) {
    final data = cardData['data'];
    final races = (data is Map<String, dynamic>)
        ? ((data['races'] as List?)
                  ?.whereType<Map<String, dynamic>>()
                  .toList() ??
              const <Map<String, dynamic>>[])
        : const <Map<String, dynamic>>[];

    if (races.isEmpty) return const SizedBox.shrink();

    final itemCount = races.length + 1;
    return SizedBox(
      height: 220,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          final isLast = index == itemCount - 1;
          final divider = isLast
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Container(
                    width: 1,
                    color: AppColors.parchment.withValues(alpha: 0.18),
                  ),
                );

          if (index == races.length) {
            return Row(
              children: [_buildJoinPublicRaceCard(context), divider],
            );
          }
          final race = races[index];
          final raceId = race['raceId'] as String? ?? '';
          final endsAtRaw = race['endsAt'];
          DateTime? endsAt;
          if (endsAtRaw is String) {
            endsAt = DateTime.tryParse(endsAtRaw);
          }
          final top3 =
              (race['top3'] as List?)
                  ?.whereType<Map<String, dynamic>>()
                  .toList() ??
              const <Map<String, dynamic>>[];
          final placement = (race['userPlacement'] as num?)?.toInt();

          return Row(
            children: [
              ActiveRaceCard(
                raceId: raceId,
                raceName: race['name'] as String? ?? 'Race',
                endsAt: endsAt,
                top3: top3,
                userPlacement: placement,
                onTap: raceId.isEmpty ? null : () => onOpenRace?.call(raceId),
              ),
              divider,
            ],
          );
        },
      ),
    );
  }

  /// Trailing card in the active-races row: tap to browse/join a public race,
  /// then refresh so a newly-joined race shows up in the row.
  Widget _buildJoinPublicRaceCard(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PublicRacesScreen(authService: authService),
          ),
        );
        await onRefresh();
      },
      child: SizedBox(
        width: 160,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.add_circle_outline,
                size: 42,
                color: AppColors.parchment.withValues(alpha: 0.92),
              ),
              const SizedBox(height: 10),
              Text(
                'JOIN A PUBLIC RACE',
                textAlign: TextAlign.center,
                style: PixelText.title(size: 13, color: AppColors.parchment),
              ),
              const SizedBox(height: 4),
              Text(
                'Find an open race',
                textAlign: TextAlign.center,
                style: PixelText.body(
                  size: 11,
                  color: AppColors.parchment.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
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
                color: AppColors.parchment,
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
            Text(
              'TODAY',
              style: PixelText.title(size: 14, color: AppColors.textMid),
            ),
            const SizedBox(height: 10),
            Text(
              'Couldn’t load your pace',
              style: PixelText.title(size: 22, color: AppColors.textDark),
            ),
            const SizedBox(height: 8),
            Text(
              error!,
              style: PixelText.body(size: 14, color: AppColors.textMid),
            ),
          ],
        ),
      );
    }

    final steps = stepData?.steps ?? 0;
    final stepsStr = _formatNumber(steps);
    final viewportHeight = MediaQuery.of(context).size.height;

    return HomePanel(
      padding: EdgeInsets.zero,
      radius: 0,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: AppColors.roofLight,
          border: Border(
            bottom: BorderSide(color: AppColors.roofDark, width: 1),
          ),
        ),
        child: CustomPaint(
          painter: const ArcadeCheckerPainter(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        displayName ?? 'You',
                        style: PixelText.title(
                          size: 24,
                          color: AppColors.parchment,
                        ).copyWith(shadows: _heroShadows),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    CoinBalanceBadge(
                      coins: authService.coins,
                      coinSize: 16,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Center(
                  child: CapybaraCustomizationPreview(
                    accessories: equippedAccessories,
                    size: viewportHeight < 760 ? 104 : 122,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'TODAY',
                  textAlign: TextAlign.center,
                  style: PixelText.title(
                    size: 12,
                    color: AppColors.parchment.withValues(alpha: 0.82),
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    stepsStr,
                    style: PixelText.title(
                      size: 58,
                      color: AppColors.parchment,
                    ).copyWith(shadows: _heroShadows),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _heroSummary(steps: steps),
                  textAlign: TextAlign.center,
                  style: PixelText.body(
                    size: 14,
                    color: AppColors.parchment.withValues(alpha: 0.88),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: StreakChip(
                        key: streakChipKey,
                        authService: authService,
                        backendApiService: backendApiService,
                        compact: true,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: PillButton(
                        label: 'SHOP',
                        icon: Icons.storefront_rounded,
                        variant: PillButtonVariant.secondary,
                        fullWidth: true,
                        onPressed: onOpenShop,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static const _heroShadows = [
    Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  Widget _buildLeaderboardHighlightsSection() {
    final cards = leaderboardHighlights.take(3).toList(growable: false);
    final state = leaderboardHighlightsState;
    final isLoading =
        leaderboardHighlightsLoading || state?.shouldShowInitialLoading == true;
    final isError = state?.isError == true && state?.hasData != true;
    if (!isLoading && !isError && cards.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _HomeSectionHeader(title: 'CLIMBING THE BOARDS'),
        const SizedBox(height: 4),
        if (isLoading && cards.isEmpty)
          const _ClimbingBoardsSkeleton()
        else if (isError)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: LoadErrorPanel(
              title: 'Couldn’t load leaderboard',
              message: 'Check your connection and try again.',
              onRetry: () {
                onRefresh();
              },
            ),
          )
        else
          _ClimbingBoardsCarousel(
            cards: cards,
            onOpenLeaderboardHighlight: onOpenLeaderboardHighlight,
          ),
      ],
    );
  }

  String _heroSummary({required int steps}) {
    if (steps >= 20000) {
      return 'Huge day. You cleared every milestone — go claim those coins.';
    }
    if (steps >= 5000) {
      return 'Nice pace. Tap the milestones below to claim your coins.';
    }
    return 'Clean pace so far. Keep walking to hit your first milestone.';
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
        const _HomeSectionHeader(title: 'SETUP'),
        if (showDisplayNamePrompt)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Add your display name',
                  style: PixelText.title(size: 20, color: AppColors.textDark),
                ),
                const SizedBox(height: 4),
                Text(
                  'Your friends need something better than a blank avatar to look for.',
                  style: PixelText.body(size: 13, color: AppColors.textMid),
                ),
                const SizedBox(height: 12),
                PillButton(
                  label: 'SET DISPLAY NAME',
                  icon: Icons.edit_rounded,
                  variant: PillButtonVariant.primary,
                  fontSize: 13,
                  fullWidth: true,
                  onPressed: _openDisplayNameScreen,
                ),
              ],
            ),
          ),
        if (showProfilePhotoPrompt)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Add a profile photo?',
                  style: PixelText.title(size: 20, color: AppColors.textDark),
                ),
                const SizedBox(height: 4),
                Text(
                  'Make it easier for friends to spot you in races and leaderboards.',
                  style: PixelText.body(size: 13, color: AppColors.textMid),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: PillButton(
                        label: 'ADD PHOTO',
                        icon: Icons.add_a_photo_rounded,
                        variant: PillButtonVariant.primary,
                        fontSize: 13,
                        fullWidth: true,
                        onPressed: _isSavingDismissal
                            ? null
                            : () => widget.onAddProfilePhoto?.call(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: PillButton(
                        label: 'NO THANKS',
                        icon: Icons.close_rounded,
                        variant: PillButtonVariant.secondary,
                        fontSize: 13,
                        fullWidth: true,
                        onPressed: _dismissProfilePhotoPrompt,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        if (showDismissedConfirmation)
          Padding(
            key: const Key('profile-photo-dismissed-confirmation'),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Text(
              'You can add one anytime in Profile.',
              style: PixelText.body(size: 13, color: AppColors.textMid),
              textAlign: TextAlign.center,
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
      backgroundColor: AppColors.roofLight,
      borderColor: AppColors.roofDark,
      radius: 0,
      child: Container(
        height: 170,
        decoration: const BoxDecoration(color: AppColors.roofLight),
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
      backgroundColor: AppColors.roofLight,
      borderColor: AppColors.roofDark,
      radius: 0,
      child: SizedBox(
        height: 170,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(0),
          child: Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(
                  color: AppColors.roofLight,
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
                                  style: PixelText.title(
                                    size: 22,
                                    color: AppColors.parchment,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  subtitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: PixelText.body(
                                    size: 14,
                                    color: AppColors.parchment.withValues(
                                      alpha: 0.85,
                                    ),
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

class _HomeSectionHeader extends StatelessWidget {
  const _HomeSectionHeader({required this.title, this.onDark = false});

  final String title;
  final bool onDark;

  static const _textShadows = [
    Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  @override
  Widget build(BuildContext context) {
    final dividerColor = onDark
        ? AppColors.parchment.withValues(alpha: 0.22)
        : AppColors.parchmentBorder.withValues(alpha: 0.72);
    final textColor =
        onDark ? AppColors.parchment : AppColors.textDark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 7),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: dividerColor)),
      ),
      child: Text(
        title,
        style: PixelText.title(
          size: 16,
          color: textColor,
        ).copyWith(shadows: _textShadows),
      ),
    );
  }
}
