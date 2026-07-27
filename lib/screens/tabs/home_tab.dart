import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/loadable.dart';
import '../../styles.dart';
import '../../widgets/app_refresh_indicator.dart';
import '../../models/step_data.dart';
import '../../utils/at_name.dart';
import '../../utils/race_display.dart';
import '../../utils/team_race.dart';
import '../../services/auth_service.dart';
import '../../services/backend_api_service.dart';
import '../../services/onboarding_state_service.dart';
import '../../widgets/arcade_fx.dart';
import '../../widgets/coach_tip.dart';
import '../../widgets/coin_balance_badge.dart';
import '../../widgets/global_event_banner.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/step_milestones_section.dart';
import '../../widgets/streak_chip.dart' show StreakChip, StreakChipState;
import '../../widgets/home_course_track.dart' show CapybaraCustomizationPreview;
import '../../widgets/home_hero_scene.dart';
import '../../widgets/race_opportunity_card.dart';
import '../../widgets/race_ui.dart';
import '../../widgets/team_scoreline.dart';
import '../display_name_screen.dart';
import '../public_races_screen.dart';
import '../get_coins_screen.dart';
import '../referral_screen.dart';

// Shared hard-offset "game piece" shadow for home cards — flat, no blur, so
// cards read as chunky physical tiles sitting on the dark felt.
const _homeCardShadow = [
  BoxShadow(color: Color(0x66000000), offset: Offset(0, 4), blurRadius: 0),
];

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
  // Equipped base character assetKey; null = capybara.
  final String? equippedAnimal;
  final Loadable<Map<String, dynamic>>? shopCatalogState;
  // Retained for backward compatibility with callers (e.g. the tutorial
  // preview) that still pass it. The add-friends hero button that consumed it
  // was removed (Friends is now a primary tab), so HomeTab no longer renders a
  // badge from this count.
  final int incomingFriendRequests;
  final VoidCallback? onOpenRacesTab;
  final VoidCallback? onOpenLeaderboardTab;

  /// Jumps to the Friends tab — the SETUP board's "add your first friend" row.
  final VoidCallback? onOpenFriendsTab;
  final VoidCallback? onOpenShop;
  final Future<void> Function()? onAddProfilePhoto;
  final Future<bool> Function()? onDismissProfilePhotoPrompt;
  final Map<String, dynamic>? raceCard;
  final bool raceCardLoading;
  final GlobalKey<StreakChipState>? streakChipKey;
  final GlobalKey<StepMilestonesSectionState>? stepMilestonesKey;
  // Optional tutorial spotlight anchors. Null in the shipped app (the wrapping
  // KeyedSubtrees are then transparent); the tutorial passes keys so its
  // overlay can measure these elements on the real home screen.
  final GlobalKey? tutorialStepsKey;
  final GlobalKey? tutorialMilestonesKey;
  final GlobalKey? tutorialShopKey;
  final GlobalKey? tutorialFriendsKey;
  final void Function(String raceId)? onOpenRace;
  final Future<void> Function(String raceId)? onJoinRaceFromCard;
  final Future<void> Function(String raceId)? onAcceptRaceInvite;
  final Future<void> Function(String raceId)? onDeclineRaceInvite;
  final void Function(String friendUserId)? onChallengeFriendBack;
  // Lets the shell patch its cached race-card batch when today's daily reward
  // is claimed, so remounting home doesn't show a stale CLAIM button.
  final VoidCallback? onDailyRewardClaimed;

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
    this.equippedAnimal,
    this.shopCatalogState,
    this.incomingFriendRequests = 0,
    this.onOpenRacesTab,
    this.onOpenLeaderboardTab,
    this.onOpenFriendsTab,
    this.onOpenShop,
    this.onAddProfilePhoto,
    this.onDismissProfilePhotoPrompt,
    this.raceCard,
    this.raceCardLoading = false,
    this.streakChipKey,
    this.stepMilestonesKey,
    this.tutorialStepsKey,
    this.tutorialMilestonesKey,
    this.tutorialShopKey,
    this.tutorialFriendsKey,
    this.onOpenRace,
    this.onJoinRaceFromCard,
    this.onAcceptRaceInvite,
    this.onDeclineRaceInvite,
    this.onChallengeFriendBack,
    this.onDailyRewardClaimed,
  });

  @override
  Widget build(BuildContext context) {
    // HomeTab is only built once onboarding is complete, so it always renders
    // the real home below — but [healthAuthorized] is no longer decorative.
    // Under v3 a user can reach this screen with steps disconnected (the
    // Android escape hatch, or an inconclusive iOS probe), and the shell pins
    // the persistent reconnect banner above the tab bar for exactly that case.
    // Home itself stays a normal home: the degraded user's step count is 0,
    // which is the truth, not an error state.
    final topInset = MediaQuery.of(context).padding.top;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final tabBarHeight = 77.5 + bottomInset;
    final bottomPadding = tabBarHeight;
    final hasProfilePhoto =
        authService.profilePhotoUrl != null &&
        authService.profilePhotoUrl!.isNotEmpty;

    return Stack(
      children: [
        // Full-screen backdrop painted behind the status-bar inset and both
        // overscroll zones: sky blue up top (behind the hero / status bar),
        // the arcade green below (behind the content / bottom overscroll).
        // A hard-stop gradient (not a Column of Expandeds — that variant
        // reproducibly fails to paint here, see golden A/B test 2026-07-12)
        // splits the fill at mid-screen in a single paint op.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.5, 0.5],
                colors: [
                  AppColors.of(context).sceneSkyTop,
                  // Night mode dims the arcade field a step further so the
                  // below-the-fold board doesn't glow against the dark chrome.
                  AppColors.of(context).isDark
                      ? AppColors.of(context).roofMid
                      : AppColors.of(context).roofLight,
                ],
              ),
            ),
          ),
        ),
        Padding(
          // No top inset: the hero scene extends up behind the status bar so
          // the sky scrolls away with the content (a fixed sky band up top
          // reads as a weird blue header once you scroll). The hero adds the
          // inset internally to keep its HUD clear of the status bar.
          padding: EdgeInsets.only(bottom: bottomPadding),
          child: AppRefreshIndicator(
            onRefresh: onRefresh,
            edgeOffset: topInset,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: _buildHeroSection(context)),
                SliverToBoxAdapter(
                  child: ColoredBox(
                    color: AppColors.of(context).isDark
                        ? AppColors.of(context).roofMid
                        : AppColors.of(context).roofLight,
                    child: CustomPaint(
                      painter: const ArcadeCheckerPainter(
                        drawBottomStripe: false,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Soft soil shadow under the hero's dirt edge so the
                            // ground blends into the green instead of hard-cutting.
                            Container(
                              height: 16,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    AppColors.of(
                                      context,
                                    ).dirtDark.withValues(alpha: 0.38),
                                    AppColors.of(
                                      context,
                                    ).dirtDark.withValues(alpha: 0.0),
                                  ],
                                ),
                              ),
                            ),
                            // Streak + shop live just under the hero scene so the
                            // world stays clean; they're the first card to bounce in.
                            StaggerIn(
                              index: 0,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  14,
                                  16,
                                  0,
                                ),
                                child: _buildQuickActionsRow(context),
                              ),
                            ),
                            // GLOBAL STEP EVENT — on-brand "2x STEPS" banner shown to
                            // every user while a step-multiplier window is live. The
                            // shared widget self-ticks the countdown and collapses on
                            // its own once the window ends.
                            if (_buildGlobalEventBanner() case final banner?)
                              StaggerIn(
                                index: 1,
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    16,
                                    16,
                                    0,
                                  ),
                                  child: banner,
                                ),
                              ),
                            // SETUP leads the page: finishing setup is a
                            // prerequisite for everything below it, and a user
                            // with no name or photo is worse off in every race
                            // they join. It collapses to a zero-
                            // height SizedBox.shrink when there's nothing to
                            // do, so a finished user sees no gap here. The
                            // stagger indices below must stay in visual order
                            // or the bounce-in cascade plays out of sequence.
                            StaggerIn(
                              index: 2,
                              child: _SetupPromptsSection(
                                displayName: displayName,
                                hasProfilePhoto: hasProfilePhoto,
                                authService: authService,
                                onDisplayNameChanged: onDisplayNameChanged,
                                onAddProfilePhoto: onAddProfilePhoto,
                                onDismissProfilePhotoPrompt:
                                    onDismissProfilePhotoPrompt,
                                showRenameChip: authService.onboardingV3Enabled,
                                // Only an actually-loaded, actually-empty
                                // friends list counts. A null state (tutorial
                                // preview) or an in-flight/failed fetch must
                                // never accuse a user with friends of having
                                // none.
                                hasNoFriends:
                                    friendsStepsState?.isSuccess == true &&
                                    friendsSteps.isEmpty,
                                onFindFriends: onOpenFriendsTab,
                              ),
                            ),
                            // Today's coins sits above the races: it's the one
                            // section that moves every single day whether or not
                            // the user is in a race, so it earns the higher
                            // slot. The stagger index moves with it — the
                            // cascade is ordered by index, not by position.
                            StaggerIn(
                              index: 3,
                              child: KeyedSubtree(
                                key: tutorialMilestonesKey,
                                child: CoachTipHost(
                                  tip: CoachTipId.milestoneClaim,
                                  store: coachTipStore,
                                  // The tutorial no longer teaches milestones;
                                  // this fires the first time the user actually
                                  // has one to claim, which is when the sentence
                                  // is finally useful.
                                  enabled:
                                      authService.onboardingV3Enabled &&
                                      (stepData?.steps ?? 0) >= 5000,
                                  child: StepMilestonesSection(
                                    key: stepMilestonesKey,
                                    authService: authService,
                                    backendApiService: backendApiService,
                                    currentSteps: stepData?.steps,
                                    // Fed by the home batch so the claim card lands
                                    // with everything else; falls back to its own
                                    // fetch on old backends.
                                    initialData:
                                        raceCard?['stepMilestones']
                                            as Map<String, dynamic>?,
                                    awaitingBatch: raceCardLoading,
                                  ),
                                ),
                              ),
                            ),
                            if (raceCard != null)
                              StaggerIn(index: 4, child: _buildRaceSection())
                            else if (raceCardLoading)
                              StaggerIn(
                                index: 4,
                                child: _buildRaceSkeletonSection(),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// On-brand "2x STEPS" banner for an active global step-multiplier event,
  /// driven by the top-level `globalEvent` on the /home/race-card response.
  /// Read defensively: an older backend omits the field (or sends it inactive /
  /// without a parseable endsAt), in which case nothing renders. The returned
  /// [GlobalEventBanner] self-ticks its countdown and collapses once the window
  /// ends, so HomeTab can stay a StatelessWidget.
  Widget? _buildGlobalEventBanner() {
    final event = raceCard?['globalEvent'];
    if (event is! Map) return null;
    if (event['active'] == false) return null;

    final endsAtRaw = event['endsAt'];
    final endsAt = endsAtRaw is String
        ? DateTime.tryParse(endsAtRaw)?.toLocal()
        : null;
    if (endsAt == null) return null;
    if (!endsAt.isAfter(DateTime.now())) return null;

    final multiplierRaw = event['multiplier'];
    final multiplier = multiplierRaw is num ? multiplierRaw.toInt() : 2;

    return GlobalEventBanner(
      key: const Key('home-global-event-banner'),
      multiplier: multiplier,
      endsAt: endsAt,
    );
  }

  /// RACES section on home — a compact launcher/rail, not the full races page.
  Widget _buildRaceSection() {
    final card = raceCard!;
    return ColoredBox(
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _HomeRaceHeader(onViewAll: onOpenRacesTab),
          if (card['state'] == 'ACTIVE_RACES')
            _buildActiveRacesRow(card)
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _buildRaceOpportunityRow(RaceCardData.fromJson(card)),
            ),
        ],
      ),
    );
  }

  Widget _buildRaceSkeletonSection() {
    return ColoredBox(
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _HomeRaceHeader(onViewAll: onOpenRacesTab),
          SizedBox(
            height: 240,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
              itemBuilder: (context, index) => const _HomeRaceSkeletonTicket(),
              separatorBuilder: (context, index) => const SizedBox(width: 12),
              itemCount: 3,
            ),
          ),
        ],
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
      height: 240,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          if (index == races.length) {
            return Padding(
              padding: const EdgeInsets.only(left: 10),
              child: _buildJoinPublicRaceCard(context),
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
          // participantCount is sent by newer backends; fall back to the
          // ranked racers we do have so older backends still render a count.
          final participantCount =
              (race['participantCount'] as num?)?.toInt() ?? top3.length;
          const itemWidth = 168.0;

          return Padding(
            padding: EdgeInsets.only(right: index == races.length - 1 ? 0 : 12),
            child: _HomeActiveRaceTicket(
              width: itemWidth,
              sweepDelay: Duration(milliseconds: 420 * index),
              raceName: race['name'] as String? ?? 'Race',
              endsAt: endsAt,
              placement: placement,
              participantCount: participantCount,
              top3: top3,
              // TR-809: team-aware ticket chrome; all fields optional so an
              // individual race (or older backend) renders exactly as before.
              race: race,
              onTap: raceId.isEmpty ? null : () => onOpenRace?.call(raceId),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRaceOpportunityRow(RaceCardData data) {
    final cardData = data.data;
    switch (data.state) {
      case RaceCardState.pendingInvite:
        final inviter = RaceCardUser.fromJson(
          cardData['inviter'] as Map<String, dynamic>?,
        );
        final raceId = cardData['raceId'] as String? ?? '';
        final participantCount =
            (cardData['participantCount'] as num?)?.toInt() ?? 0;
        final durationHours = (cardData['durationHours'] as num?)?.toInt() ?? 0;
        return _HomeRaceActionRow(
          label: 'INVITE',
          title: '${atName(inviter?.displayName ?? 'Someone')} challenged you',
          subtitle:
              '${_formatDuration(durationHours)} · $participantCount racers',
          primaryLabel: 'ACCEPT',
          secondaryLabel: 'DECLINE',
          onPrimary: onAcceptRaceInvite == null || raceId.isEmpty
              ? null
              : () => onAcceptRaceInvite!(raceId),
          onSecondary: onDeclineRaceInvite == null || raceId.isEmpty
              ? null
              : (_) => onDeclineRaceInvite!(raceId),
        );
      case RaceCardState.activeRace:
        final raceId = cardData['raceId'] as String? ?? '';
        final name = cardData['name'] as String? ?? 'Race';
        final endsAt = DateTime.tryParse(cardData['endsAt'] as String? ?? '');
        return _HomeRaceActionRow(
          label: 'ACTIVE',
          title: name,
          subtitle: endsAt == null
              ? 'Race in progress'
              : '${_formatTimeLeft(endsAt)} left',
          primaryLabel: 'VIEW',
          onPrimary: onOpenRace == null || raceId.isEmpty
              ? null
              : () => onOpenRace!(raceId),
        );
      case RaceCardState.friendRacing:
        final raceId = cardData['raceId'] as String? ?? '';
        final friend = RaceCardUser.fromJson(
          cardData['friend'] as Map<String, dynamic>?,
        );
        final participants = ((cardData['participants'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .length;
        final isPublicJoinable = cardData['isPublicJoinable'] as bool? ?? false;
        return _HomeRaceActionRow(
          label: 'LIVE',
          title: '${atName(friend?.displayName ?? 'A friend')} is racing',
          subtitle: participants > 0
              ? '$participants racers'
              : 'A race is happening now',
          primaryLabel: isPublicJoinable ? 'JOIN' : 'OPEN',
          onPrimary:
              isPublicJoinable &&
                  onJoinRaceFromCard != null &&
                  raceId.isNotEmpty
              ? () => onJoinRaceFromCard!(raceId)
              : onOpenRacesTab,
        );
      case RaceCardState.friendFinished:
        final friend = RaceCardUser.fromJson(
          cardData['friend'] as Map<String, dynamic>?,
        );
        final raceName = cardData['raceName'] as String? ?? 'a race';
        return _HomeRaceActionRow(
          label: 'FINISHED',
          title:
              '${atName(friend?.displayName ?? 'A friend')} finished $raceName',
          subtitle: 'Start a rematch when you are ready',
          primaryLabel: 'CHALLENGE',
          onPrimary: onChallengeFriendBack == null || friend == null
              ? null
              : () => onChallengeFriendBack!(friend.userId),
        );
      case RaceCardState.publicRace:
        final raceId = cardData['raceId'] as String? ?? '';
        final name = raceDisplayName(
          cardData['seedKind'] as String?,
          cardData['name'] as String? ?? 'Public Race',
        );
        final participantCount =
            (cardData['participantCount'] as num?)?.toInt() ?? 0;
        final endsAt = DateTime.tryParse(cardData['endsAt'] as String? ?? '');
        return _HomeRaceActionRow(
          label: 'PUBLIC',
          title: name,
          subtitle:
              '$participantCount racing${endsAt == null ? '' : ' · ${_formatTimeLeft(endsAt)} left'}',
          primaryLabel: 'JOIN',
          onPrimary: onJoinRaceFromCard == null || raceId.isEmpty
              ? null
              : () => onJoinRaceFromCard!(raceId),
        );
      case RaceCardState.empty:
        return _HomeRaceActionRow(
          label: 'OPEN',
          title: 'Race your friends',
          subtitle: 'Start with friends or find a public race.',
          primaryLabel: 'RACES',
          secondaryLabel: 'INVITE',
          onPrimary: onOpenRacesTab,
          onSecondary: (ctx) {
            // Open the referral screen so the invite carries the user's real
            // /r/BARA-<code> link (earns both sides coins), not a bare store URL.
            Navigator.of(ctx).push(
              MaterialPageRoute(
                builder: (_) => ReferralScreen(
                  authService: authService,
                  backendApiService: backendApiService,
                ),
              ),
            );
          },
        );
    }
  }

  String _formatTimeLeft(DateTime endsAt) {
    final remaining = endsAt.difference(DateTime.now());
    if (remaining.isNegative) return 'ending soon';
    if (remaining.inDays > 0) {
      return '${remaining.inDays}d ${remaining.inHours.remainder(24)}h';
    }
    if (remaining.inHours > 0) {
      return '${remaining.inHours}h ${remaining.inMinutes.remainder(60)}m';
    }
    if (remaining.inMinutes > 0) {
      return '${remaining.inMinutes}m';
    }
    return '${remaining.inSeconds}s';
  }

  String _formatDuration(int hours) {
    if (hours <= 0) return 'Race';
    if (hours >= 24) {
      final days = (hours / 24).round();
      return '$days-day race';
    }
    return '${hours}h race';
  }

  /// Trailing card in the active-races row: tap to browse/join a public race,
  /// then refresh so a newly-joined race shows up in the row.
  Widget _buildJoinPublicRaceCard(BuildContext context) {
    final palette = AppColors.of(context);
    final publicAccent = palette.isDark
        ? palette.pillTerra
        : palette.pillGoldDark;
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
        width: 136,
        height: 222,
        child: PulseGlow(
          color: publicAccent,
          borderRadius: 14,
          minAlpha: 0.14,
          maxAlpha: 0.38,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.of(context).parchment,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: publicAccent, width: 2),
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 18, 12, 16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    WobbleBadge(
                      child: Icon(
                        key: const Key('home-public-race-add-icon'),
                        Icons.add_circle_rounded,
                        size: 42,
                        color: palette.isDark
                            ? publicAccent
                            : palette.pillGoldShadow,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'PUBLIC',
                      textAlign: TextAlign.center,
                      style: PixelText.title(
                        size: 17,
                        color: AppColors.of(context).textDark,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Find a race',
                      textAlign: TextAlign.center,
                      style: PixelText.body(
                        size: 12,
                        color: AppColors.of(context).textMid,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The hero is the capybara's world: generated pixel sky + sun, drifting
  /// clouds, and the course scene's grass-and-dirt ground, with the
  /// dressed-up capybara walking on the grass and today's steps floating as
  /// a game HUD.
  Widget _buildHeroSection(BuildContext context) {
    final viewportHeight = MediaQuery.of(context).size.height;
    final compact = viewportHeight < 760;
    // The scene runs edge-to-edge behind the status bar; the inset is added
    // to the scene height and to every top-anchored element so the HUD stays
    // clear of the system chrome.
    final topInset = MediaQuery.of(context).padding.top;
    final heroHeight = (compact ? 352.0 : 404.0) + topInset;
    const groundHeight = 84.0;
    final capySize = compact ? 126.0 : 148.0;

    final Widget hud;
    if (isLoading && stepData == null) {
      // Mirror the loaded HUD (big step-count block above a small label bar)
      // rather than a bare spinner. Uses the same static-bar skeleton style as
      // the race-strip tickets below, in a parchment tone so it reads on the
      // sky. Sits where the real number lands via the HUD's Positioned offset.
      hud = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: compact ? 168 : 196,
            height: compact ? 52 : 60,
            decoration: BoxDecoration(
              color: AppColors.of(context).textLight.withValues(alpha: 0.30),
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: 120,
            height: 13,
            decoration: BoxDecoration(
              color: AppColors.of(context).textLight.withValues(alpha: 0.26),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ],
      );
    } else if (error != null) {
      hud = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Couldn’t load your pace',
            textAlign: TextAlign.center,
            style: PixelText.title(
              size: 22,
              color: AppColors.of(context).textLight,
            ).copyWith(shadows: _heroShadows),
          ),
          const SizedBox(height: 8),
          Text(
            error!,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: PixelText.body(
              size: 14,
              color: AppColors.of(context).textLight.withValues(alpha: 0.88),
            ).copyWith(shadows: _heroShadows),
          ),
        ],
      );
    } else {
      final steps = stepData?.steps ?? 0;
      hud = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          KeyedSubtree(
            key: tutorialStepsKey,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: CountUpText(
                value: steps,
                format: _formatNumber,
                style: PixelText.title(
                  size: compact ? 56 : 64,
                  color: AppColors.of(context).textLight,
                ).copyWith(shadows: _heroHudShadows),
              ),
            ),
          ),
          const SizedBox(height: 2),
          // Label under the number so it can never collide with the
          // name/coins row above.
          Text(
            'STEPS TODAY',
            textAlign: TextAlign.center,
            style: PixelText.title(
              size: 13,
              color: AppColors.of(context).textLight.withValues(alpha: 0.85),
            ).copyWith(shadows: _heroShadows, letterSpacing: 3),
          ),
        ],
      );
    }

    return SizedBox(
      height: heroHeight,
      child: HomeHeroScene(
        groundHeight: groundHeight,
        // Slide the ground left so the walking capybara reads as moving
        // forward instead of jogging in place. Tuned against the 6-frame /
        // 480ms walk cycle — fast enough to sell the motion, slow enough that
        // it doesn't pull the eye off the step count.
        groundScrollSpeed: 26,
        child: Stack(
          children: [
            Positioned(
              left: 20,
              // Keep the name/coins clear of the overlaid help button.
              right: 58,
              top: topInset + 12,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      atName(displayName ?? 'You'),
                      style: PixelText.title(
                        size: 24,
                        color: AppColors.of(context).textLight,
                      ).copyWith(shadows: _heroShadows),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 10),
                  CoinBalanceBadge(
                    coins: authService.coins,
                    coinSize: 16,
                    // "+" = earn more coins -> the Get Coins hub
                    // (watch an ad, invite friends, daily box).
                    onAddTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => GetCoinsScreen(
                          authService: authService,
                          backendApiService: backendApiService,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              top: topInset + (compact ? 52 : 72),
              child: hud,
            ),
            // The wooden pace-line trail sign that used to stand in the dirt
            // strip here is gone: the line was narration the scene didn't need,
            // and the plank crowded the capybara.
            // The capybara stands on the grass line. The walk sprite has
            // ~22% transparent padding below the feet, so pull the widget
            // down by that much to land the feet a few px into the grass.
            Positioned(
              left: 0,
              right: 0,
              bottom: groundHeight - 4 - capySize * 0.22,
              child: Center(
                child: CapybaraCustomizationPreview(
                  accessories: equippedAccessories,
                  animal: equippedAnimal,
                  size: capySize,
                  showShadow: false,
                ),
              ),
            ),
            // Item 8: the hero "?" help button was removed — the baked-in sun in
            // the sky PNG visually covered it. Help/tutorial is still reachable
            // from the Profile tab, so nothing is orphaned.
          ],
        ),
      ),
    );
  }

  /// Streak + shop, first row under the hero. Same widgets and wiring as the
  /// old in-hero row — only their home moved.
  Widget _buildQuickActionsRow(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: StreakChip(
            key: streakChipKey,
            authService: authService,
            backendApiService: backendApiService,
            compact: true,
            // Fed by the home batch so the CLAIM button lands with everything
            // else; falls back to its own fetch on old backends.
            initialData: raceCard?['dailyReward'] as Map<String, dynamic>?,
            awaitingBatch: raceCardLoading,
            onClaimedToday: onDailyRewardClaimed,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: KeyedSubtree(
            key: tutorialShopKey,
            child: PillButton(
              label: 'SHOP',
              icon: Icons.storefront_rounded,
              variant: PillButtonVariant.secondary,
              fullWidth: true,
              onPressed: onOpenShop,
            ),
          ),
        ),
      ],
    );
  }

  static const _heroShadows = [
    Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  // Chunkier drop for the big HUD number so it reads like game UI over sky.
  static const _heroHudShadows = [
    Shadow(color: Color(0x59102A3C), blurRadius: 0, offset: Offset(0, 4)),
    Shadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 2)),
  ];

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

/// The SETUP board: one parchment panel carrying every outstanding setup ask,
/// stacked and separated by a hairline rule.
///
/// One board, not one card per prompt. These are all the same kind of thing —
/// a short question with two answers — and a user with a name prompt AND a
/// photo prompt used to see two competing panels with a gap between them.
class _SetupBoard extends StatelessWidget {
  const _SetupBoard({required this.entries});

  final List<_SetupEntry> entries;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final rows = <Widget>[];
    for (var i = 0; i < entries.length; i++) {
      if (i > 0) {
        rows.add(
          Divider(
            height: 1,
            thickness: 2,
            color: colors.parchmentBorder.withValues(alpha: 0.55),
            indent: 16,
            endIndent: 16,
          ),
        );
      }
      rows.add(entries[i]);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.parchment,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: colors.roofDark.withValues(alpha: 0.4),
            width: 2,
          ),
          boxShadow: _homeCardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        ),
      ),
    );
  }
}

/// One ask inside [_SetupBoard]: a chunky icon in a tinted well, the question
/// and its reason, then the answers.
class _SetupEntry extends StatelessWidget {
  const _SetupEntry({
    required this.icon,
    this.iconKey,
    required this.title,
    required this.subtitle,
    required this.actions,
  });

  final IconData icon;
  final Key? iconKey;
  final String title;
  final String subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The well is what keeps a 24px glyph from floating loose beside
              // 20px display type — it gives the icon a footprint the title
              // can sit against.
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors.parchmentLight,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colors.parchmentBorder, width: 2),
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  key: iconKey,
                  size: 22,
                  color: colors.isDark ? colors.accentLight : colors.roofMid,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: PixelText.title(size: 19, color: colors.textDark),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: PixelText.body(size: 13, color: colors.textMid),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(children: actions),
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
    this.showRenameChip = false,
    this.hasNoFriends = false,
    this.onFindFriends,
  });

  final String? displayName;
  final bool hasProfilePhoto;
  final AuthService authService;
  final VoidCallback onDisplayNameChanged;
  final Future<void> Function()? onAddProfilePhoto;
  final Future<bool> Function()? onDismissProfilePhotoPrompt;

  /// The friends list came back and it was empty. Racing alone is the single
  /// biggest reason a new account goes quiet, so an empty roster is setup work
  /// exactly like a missing photo is.
  final bool hasNoFriends;

  /// Opens the Friends tab. Null hides the row (nowhere to send them).
  final VoidCallback? onFindFriends;

  /// Whether to offer the one-time rename chip. Generated names
  /// (SwiftCapybara07) are good friction-reduction, but users don't know they
  /// are changeable — and nothing else on Home says so.
  final bool showRenameChip;

  @override
  State<_SetupPromptsSection> createState() => _SetupPromptsSectionState();
}

class _SetupPromptsSectionState extends State<_SetupPromptsSection> {
  Timer? _dismissTimer;
  bool _showDismissedConfirmation = false;
  bool _isSavingDismissal = false;
  final OnboardingStateService _onboardingState = OnboardingStateService();
  bool _showRenameChip = false;

  @override
  void initState() {
    super.initState();
    _resolveRenameChip();
  }

  /// Decides whether to offer the rename chip, from the server ledger when the
  /// backend provides one and from the device-local ledger otherwise.
  ///
  /// The server path exists because "this account knows its generated name is
  /// changeable" is a property of the account, not the handset — the local keys
  /// are wiped by `signOut()`, which is why the chip used to come back after
  /// every sign-out/sign-in cycle.
  Future<void> _resolveRenameChip() async {
    if (!widget.showRenameChip) return;
    final name = widget.displayName?.trim();
    if (name == null || name.isEmpty) return;

    final auth = widget.authService;
    if (auth.hasServerRenameChipState) {
      if (auth.renameChipDismissedAt != null) return;
      if ((auth.renameChipShownCount ?? 0) >=
          OnboardingStateService.maxRenameChipShows) {
        return;
      }
      if (!mounted) return;
      setState(() => _showRenameChip = true);
      _countOneImpression(auth: auth);
      return;
    }

    // Older backend: neither field ever arrived, so fall back to the device-
    // local ledger. Absent fields must never read as "0 / never dismissed".
    if (!await _onboardingState.shouldShowRenameChip()) return;
    if (!mounted) return;
    await _countOneImpression(auth: null);
    if (!mounted) return;
    setState(() => _showRenameChip = true);
  }

  /// Records at most one chip impression per app session, whichever ledger is
  /// in play. Home lives in a `PageView` with no keep-alive, so
  /// [_resolveRenameChip] re-runs on every tab swipe — uncounted, the
  /// three-show budget burns out in three swipes. That defect is independent of
  /// where the state is stored, so the guard covers the local path too.
  ///
  /// [auth] non-null selects the server ledger; null selects the local one.
  Future<void> _countOneImpression({required AuthService? auth}) async {
    if (OnboardingStateService.renameChipCountedThisSession) return;
    OnboardingStateService.markRenameChipCountedThisSession();
    if (auth != null) {
      // Fire-and-forget: an older backend 404s this and must never toast.
      unawaited(auth.recordRenameChipShown());
      return;
    }
    await _onboardingState.recordRenameChipShown();
  }

  Future<void> _openRenameFromChip() async {
    // Tapping is the strongest possible signal that the message landed, so it
    // retires the chip permanently — whether or not the name actually changes.
    // The write is optimistic and never reverts: a failed POST must not
    // resurrect a nudge the user explicitly retired.
    if (widget.authService.hasServerRenameChipState) {
      unawaited(widget.authService.dismissRenameChip());
    } else {
      await _onboardingState.dismissRenameChip();
    }
    if (mounted) setState(() => _showRenameChip = false);
    await _openDisplayNameScreen();
  }

  /// "KEEP MY NAME" — the same permanent retirement, minus the trip to the
  /// rename screen. A prompt with only one answer is a chore; giving the happy
  /// path an explicit button is what makes this a question.
  Future<void> _keepGeneratedName() async {
    if (widget.authService.hasServerRenameChipState) {
      unawaited(widget.authService.dismissRenameChip());
    } else {
      await _onboardingState.dismissRenameChip();
    }
    if (mounted) setState(() => _showRenameChip = false);
  }

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

    final showRenameChip = _showRenameChip && widget.displayName != null;
    final showFriendPrompt =
        widget.hasNoFriends && widget.onFindFriends != null;

    if (!showDisplayNamePrompt &&
        !showProfilePhotoPrompt &&
        !showDismissedConfirmation &&
        !showFriendPrompt &&
        !showRenameChip) {
      return const SizedBox.shrink();
    }

    final colors = AppColors.of(context);

    // Every SETUP ask is the same shape — icon, question, two answers — so they
    // share one board instead of each floating in its own card. The old mix of
    // a bare pill chip next to a full card read as two unrelated features that
    // happened to land under the same header.
    final entries = <_SetupEntry>[
      if (showRenameChip)
        _SetupEntry(
          icon: Icons.badge_rounded,
          title: 'Want a different name?',
          subtitle:
              'We picked @${widget.displayName} for you. It is what friends '
              'look for in a race — keep it, or make it yours.',
          actions: [
            Expanded(
              child: PillButton(
                key: const Key('home-rename-chip'),
                label: 'CHANGE IT',
                icon: Icons.edit_rounded,
                variant: PillButtonVariant.primary,
                fontSize: 13,
                fullWidth: true,
                onPressed: _openRenameFromChip,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: PillButton(
                key: const Key('home-keep-name'),
                label: 'KEEP IT',
                icon: Icons.check_rounded,
                variant: PillButtonVariant.secondary,
                fontSize: 13,
                fullWidth: true,
                onPressed: _keepGeneratedName,
              ),
            ),
          ],
        ),
      if (showDisplayNamePrompt)
        _SetupEntry(
          icon: Icons.edit_rounded,
          title: 'Add your display name',
          subtitle:
              'Your friends need something better than a blank avatar to look for.',
          actions: [
            Expanded(
              child: PillButton(
                label: 'SET DISPLAY NAME',
                icon: Icons.edit_rounded,
                variant: PillButtonVariant.primary,
                fontSize: 13,
                fullWidth: true,
                onPressed: _openDisplayNameScreen,
              ),
            ),
          ],
        ),
      if (showProfilePhotoPrompt)
        _SetupEntry(
          icon: Icons.add_a_photo_rounded,
          iconKey: const Key('home-profile-photo-prompt-icon'),
          title: 'Add a profile photo?',
          subtitle:
              'Make it easier for friends to spot you in races and leaderboards.',
          actions: [
            Expanded(
              child: PillButton(
                label: 'ADD PHOTO',
                icon: Icons.add_a_photo_rounded,
                variant: colors.isDark
                    ? PillButtonVariant.accent
                    : PillButtonVariant.primary,
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
      if (showFriendPrompt)
        _SetupEntry(
          icon: Icons.group_add_rounded,
          iconKey: const Key('home-add-friend-prompt-icon'),
          title: 'Add your first friend',
          subtitle:
              'Races are better with someone to beat. Add a friend and you can '
              'invite them straight into one.',
          actions: [
            Expanded(
              child: PillButton(
                key: const Key('home-add-friend-cta'),
                label: 'FIND FRIENDS',
                icon: Icons.person_add_alt_1_rounded,
                variant: PillButtonVariant.primary,
                fontSize: 13,
                fullWidth: true,
                onPressed: widget.onFindFriends,
              ),
            ),
          ],
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _HomeSectionHeader(title: 'SETUP'),
        if (entries.isNotEmpty) _SetupBoard(entries: entries),
        if (showDismissedConfirmation)
          Padding(
            key: const Key('profile-photo-dismissed-confirmation'),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Text(
              'You can add one anytime in Profile.',
              style: PixelText.body(
                size: 13,
                color: AppColors.of(context).textLight.withValues(alpha: 0.8),
              ),
              textAlign: TextAlign.center,
            ),
          ),
      ],
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
        color: AppColors.of(context).parchmentBorder.withValues(alpha: 0.46),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _SkeletonCircle extends StatelessWidget {
  const _SkeletonCircle({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.of(context).parchmentBorder.withValues(alpha: 0.46),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _HomeRaceHeader extends StatelessWidget {
  const _HomeRaceHeader({this.onViewAll});

  final VoidCallback? onViewAll;

  static const _textShadows = [
    Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  @override
  Widget build(BuildContext context) {
    // No top rule. The old 12%-alpha white `feltLine` hairline belonged to the
    // retired felt-table look; against the current card borders and the
    // _SectionTick marker it read as a stray white line across the page — in
    // both palettes, since the token had no night override.
    return Padding(
      padding: EdgeInsets.zero,
      child: Container(
        width: double.infinity,
        // Top is half the section default: this header follows the Today's
        // coins card, and 16 here stacked on that card's own bottom padding
        // left the RACES label stranded midway between the two sections.
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 9),
        child: Row(
          children: [
            const _SectionTick(),
            const SizedBox(width: 8),
            Text(
              'RACES',
              style: PixelText.title(
                size: 20,
                color: AppColors.of(context).textLight,
              ).copyWith(shadows: _textShadows),
            ),
            const Spacer(),
            if (onViewAll != null)
              GestureDetector(
                onTap: onViewAll,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.24),
                    ),
                  ),
                  child: Text(
                    'VIEW ALL',
                    style: PixelText.title(
                      size: 11,
                      color: AppColors.of(
                        context,
                      ).textLight.withValues(alpha: 0.9),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HomeRaceSkeletonTicket extends StatelessWidget {
  const _HomeRaceSkeletonTicket();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 168,
      height: 222,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.of(context).parchment.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.of(context).roofDark.withValues(alpha: 0.18),
            width: 2,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const _SkeletonBar(width: 48, height: 22),
              const SizedBox(height: 14),
              const _SkeletonBar(width: 104, height: 14),
              const SizedBox(height: 6),
              const _SkeletonBar(width: 82, height: 14),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  _SkeletonCircle(size: 34),
                  SizedBox(width: 4),
                  _SkeletonCircle(size: 34),
                  SizedBox(width: 4),
                  _SkeletonCircle(size: 34),
                ],
              ),
              const Spacer(),
              const _SkeletonBar(width: 92, height: 14),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeActiveRaceTicket extends StatelessWidget {
  const _HomeActiveRaceTicket({
    required this.width,
    required this.raceName,
    required this.endsAt,
    required this.placement,
    required this.participantCount,
    required this.top3,
    required this.onTap,
    this.race = const {},
    this.sweepDelay = Duration.zero,
  });

  final double width;
  final String raceName;
  final DateTime? endsAt;
  final int? placement;
  final int participantCount;
  final List<Map<String, dynamic>> top3;
  final VoidCallback? onTap;

  /// The raw race-card entry — read defensively for TR-809 team chrome.
  final Map<String, dynamic> race;

  /// Staggers the shine sweep so a rail of tickets doesn't flash in unison.
  final Duration sweepDelay;

  String _compactTimeLeft(DateTime endsAt) {
    final remaining = endsAt.difference(DateTime.now());
    if (remaining.isNegative) return 'ENDING SOON';
    if (remaining.inDays > 0) return '${remaining.inDays}D LEFT';
    if (remaining.inHours > 0) return '${remaining.inHours}H LEFT';
    if (remaining.inMinutes > 0) return '${remaining.inMinutes}M LEFT';
    return '${remaining.inSeconds}S LEFT';
  }

  /// Header band tint keyed to the user's placement — gold/silver/bronze for
  /// podium spots, course green otherwise.
  Color _bandColor(BuildContext context) {
    final colors = AppColors.of(context);
    switch (placement) {
      case 1:
        return colors.medalGold.withValues(alpha: 0.34);
      case 2:
        return colors.medalSilver.withValues(alpha: 0.40);
      case 3:
        return colors.medalBronze.withValues(alpha: 0.34);
      default:
        return colors.roofLight.withValues(alpha: 0.22);
    }
  }

  /// The periodic shine sweep reads as a stray light flash on the dark night
  /// cards, so it only runs on the light theme.
  Widget _maybeShineSweep(BuildContext context, {required Widget child}) {
    if (AppColors.of(context).isDark) return child;
    return ShineSweep(delay: sweepDelay, child: child);
  }

  @override
  Widget build(BuildContext context) {
    final endsAt = this.endsAt;
    final isTeamRace = TeamRace.isTeamRace(race);
    final teamSize = TeamRace.teamSize(race);
    final teamTotals = isTeamRace ? TeamRace.listTeamTotals(race) : null;
    final info = [
      '$participantCount racer${participantCount == 1 ? '' : 's'}',
      if (endsAt != null) _compactTimeLeft(endsAt),
    ].join(' · ');

    return SizedBox(
      width: width,
      height: 222,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              color: AppColors.of(context).parchment,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.of(context).roofDark.withValues(alpha: 0.55),
                width: 2,
              ),
              boxShadow: _homeCardShadow,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _maybeShineSweep(
                context,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      height: 38,
                      decoration: BoxDecoration(
                        color: _bandColor(context),
                        border: Border(
                          bottom: BorderSide(
                            color: AppColors.of(
                              context,
                            ).roofDark.withValues(alpha: 0.16),
                            width: 2,
                          ),
                        ),
                      ),
                      child: Center(
                        child: WobbleBadge(
                          // TR-809/TR-685: inside a team race the ticket
                          // leads with the team format, not an individual
                          // placement.
                          child: isTeamRace && teamSize != null
                              ? TeamFormatChip(teamSize: teamSize)
                              : PlacementPill(placement: placement),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              raceName,
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              style: PixelText.title(
                                size: 17,
                                color: AppColors.of(context).textDark,
                              ),
                            ),
                            const Spacer(),
                            RacerAvatarStack(entries: top3),
                            const SizedBox(height: 8),
                            // TR-809: compact rope-knot scoreline where the
                            // racer-count line shows on individual tickets.
                            if (teamTotals != null)
                              TeamScoreline(
                                teamAName: TeamRace.teamName(
                                  race,
                                  RaceTeam.teamA,
                                ),
                                teamBName: TeamRace.teamName(
                                  race,
                                  RaceTeam.teamB,
                                ),
                                teamATotal: teamTotals.$1,
                                teamBTotal: teamTotals.$2,
                              )
                            else
                              Text(
                                info,
                                maxLines: 1,
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                                style: PixelText.body(
                                  size: 12,
                                  color: AppColors.of(context).textMid,
                                ),
                              ),
                            const SizedBox(height: 10),
                            PulseGlow(
                              borderRadius: 8,
                              child: Container(
                                height: 32,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: AppColors.of(context).pillGold,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: AppColors.of(context).pillGoldDark,
                                    width: 1.5,
                                  ),
                                ),
                                child: Text(
                                  'VIEW RACE',
                                  style: PixelText.title(
                                    size: 12,
                                    color: AppColors.of(context).textDark,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeRaceActionRow extends StatelessWidget {
  const _HomeRaceActionRow({
    required this.label,
    required this.title,
    required this.subtitle,
    required this.primaryLabel,
    this.secondaryLabel,
    this.onPrimary,
    this.onSecondary,
  });

  final String label;
  final String title;
  final String subtitle;
  final String primaryLabel;
  final String? secondaryLabel;
  final VoidCallback? onPrimary;
  // Receives the secondary button's own BuildContext so callers (e.g. share)
  // can anchor an iPad popover to the button's rect.
  final void Function(BuildContext)? onSecondary;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.of(context).parchment,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.of(context).roofDark.withValues(alpha: 0.4),
          width: 2,
        ),
        boxShadow: _homeCardShadow,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: PixelText.title(
                      size: 10,
                      // `successText`, not `roofMid`: roofMid is a SURFACE
                      // green, and at night (#214637 on the #1B2A34 parchment
                      // card) the eyebrow — INVITE / ACTIVE / LIVE / FINISHED
                      // / PUBLIC / OPEN — vanished at ~1.2:1. successText is
                      // the text-role token: identical to roofMid by day, and
                      // a legible #8CC6A8 at night.
                      color: AppColors.of(context).successText,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PixelText.title(
                      size: 17,
                      color: AppColors.of(context).textDark,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PixelText.body(
                      size: 12,
                      color: AppColors.of(context).textMid,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PulseGlow(
                  borderRadius: 7,
                  child: _SmallRaceButton(
                    label: primaryLabel,
                    onPressed: onPrimary,
                  ),
                ),
                if (secondaryLabel != null) ...[
                  const SizedBox(height: 6),
                  Builder(
                    builder: (btnContext) => _SmallRaceButton(
                      label: secondaryLabel!,
                      onPressed: onSecondary == null
                          ? null
                          : () => onSecondary!(btnContext),
                      muted: true,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallRaceButton extends StatelessWidget {
  const _SmallRaceButton({
    required this.label,
    required this.onPressed,
    this.muted = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onPressed == null ? 0.52 : 1,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          width: 78,
          padding: const EdgeInsets.symmetric(vertical: 7),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: muted
                ? AppColors.of(context).parchmentLight
                : AppColors.of(context).pillGold,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: muted
                  ? AppColors.of(context).parchmentBorder
                  : AppColors.of(context).pillGoldDark,
              width: 1.5,
            ),
          ),
          // The box is a fixed 78pt, so the longest label it is ever handed
          // ("CHALLENGE") ellipsized at every screen width — the same silent
          // truncation as PillButton's "EXTRA SPIN" (item 4). Shrink to fit
          // instead; ellipsis stays as the last-resort backstop.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PixelText.title(
                size: 10,
                color: muted
                    ? AppColors.of(context).textMid
                    : AppColors.of(context).textDark,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeSectionHeader extends StatelessWidget {
  const _HomeSectionHeader({required this.title});

  final String title;

  static const _textShadows = [
    Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  @override
  Widget build(BuildContext context) {
    // See _HomeRaceHeader: the `feltLine` top rule is gone from both headers.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 9),
      child: Row(
        children: [
          const _SectionTick(),
          const SizedBox(width: 8),
          Text(
            title,
            style: PixelText.title(
              size: 20,
              color: AppColors.of(context).textLight,
            ).copyWith(shadows: _textShadows),
          ),
        ],
      ),
    );
  }
}

/// Small gold tab in front of section titles — the one recurring flourish in
/// the below-the-fold card language.
class _SectionTick extends StatelessWidget {
  const _SectionTick();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 18,
      decoration: BoxDecoration(
        color: AppColors.of(context).pillGold,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: AppColors.of(context).pillGoldDark),
      ),
    );
  }
}
