import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/loadable.dart';
import '../../styles.dart';
import '../../models/step_data.dart';
import '../../services/auth_service.dart';
import '../../services/backend_api_service.dart';
import '../../widgets/app_avatar.dart';
import '../../widgets/coin_balance_badge.dart';
import '../../widgets/step_milestones_section.dart';
import '../../widgets/streak_chip.dart' show StreakChip, StreakChipState;
import '../../widgets/active_race_card.dart';
import '../../widgets/home_chrome.dart';
import '../../widgets/home_course_track.dart' show CapybaraCustomizationPreview;
import '../../widgets/loading_skeleton.dart';
import '../../widgets/race_opportunity_card.dart';
import '../../widgets/retro_card.dart';
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
  final VoidCallback? onOpenProfile;
  final Future<void> Function()? onAddProfilePhoto;
  final Future<bool> Function()? onDismissProfilePhotoPrompt;
  final int incomingFriendRequests;
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
    this.onOpenProfile,
    this.onAddProfilePhoto,
    this.onDismissProfilePhotoPrompt,
    this.incomingFriendRequests = 0,
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
                    if (raceCard != null) ...[
                      const SizedBox(height: 16),
                      // New (opt-in) ACTIVE_RACES state → horizontal row of
                      // active-race cards. Any other state keeps rendering the
                      // existing RaceOpportunityCard exactly as before
                      // (invites / friend racing / public / empty).
                      if (raceCard!['state'] == 'ACTIVE_RACES')
                        _buildActiveRacesRow(raceCard!)
                      else
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: RaceOpportunityCard(
                            data: RaceCardData.fromJson(raceCard!),
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

    return SizedBox(
      height: 248,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        // +1 for the trailing "join a public race" card.
        itemCount: races.length + 1,
        itemBuilder: (context, index) {
          if (index == races.length) {
            return _buildJoinPublicRaceCard(context);
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

          return Padding(
            // A card always follows (another race or the join card).
            padding: const EdgeInsets.only(right: 10),
            child: ActiveRaceCard(
              raceId: raceId,
              raceName: race['name'] as String? ?? 'Race',
              endsAt: endsAt,
              top3: top3,
              userPlacement: placement,
              onTap: raceId.isEmpty ? null : () => onOpenRace?.call(raceId),
            ),
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
        width: 200,
        child: RetroCard(
          padding: const EdgeInsets.all(12),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.add_circle_outline,
                  size: 44,
                  color: AppColors.accent,
                ),
                const SizedBox(height: 12),
                Text(
                  'JOIN A PUBLIC RACE',
                  textAlign: TextAlign.center,
                  style: PixelText.title(size: 14, color: AppColors.textDark),
                ),
                const SizedBox(height: 6),
                Text(
                  'Find an open race to enter',
                  textAlign: TextAlign.center,
                  style: PixelText.body(size: 11, color: AppColors.textMid),
                ),
              ],
            ),
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
    final stepsStr = _formatNumber(steps);
    final viewportHeight = MediaQuery.of(context).size.height;

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
                        badgeCount: incomingFriendRequests,
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
                            child: Text(
                              stepsStr,
                              style: HomeText.display(
                                size: 58,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _heroSummary(steps: steps),
                            textAlign: TextAlign.center,
                            style: HomeText.body(
                              size: 14,
                              color: Colors.white.withValues(alpha: 0.82),
                              weight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 14),
                          StreakChip(
                            key: streakChipKey,
                            authService: authService,
                            backendApiService: backendApiService,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Text('CLIMBING THE BOARDS', style: HomeText.label(size: 13)),
        ),
        const SizedBox(height: 10),
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
                  'Make it easier for friends to spot you in races and leaderboards.',
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
