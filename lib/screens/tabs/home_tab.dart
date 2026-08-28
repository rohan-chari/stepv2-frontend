import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/loadable.dart';
import '../../models/giveaway.dart';
import '../../models/home_race_suggestion.dart';
import '../../models/next_race.dart';
import '../../styles.dart';
import '../../widgets/app_refresh_indicator.dart';
import '../../models/step_data.dart';
import '../../utils/at_name.dart';
import '../../utils/race_display.dart';
import '../../utils/race_participant_display.dart';
import '../../utils/team_race.dart';
import '../../services/auth_service.dart';
import '../../services/ad_service.dart';
import '../../services/backend_api_service.dart';
import '../../services/onboarding_state_service.dart';
import '../../widgets/arcade_fx.dart';
import '../../widgets/coach_tip.dart';
import '../../widgets/coin_balance_badge.dart';
import '../../widgets/coin_glyph.dart';
import '../../widgets/game_container.dart';
import '../../widgets/global_event_banner.dart';
import '../../widgets/feedback_sheet.dart';
import '../../widgets/home_giveaway_banner.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/step_milestones_section.dart';
import '../../widgets/streak_chip.dart' show StreakChip, StreakChipState;
import '../../widgets/home_course_track.dart' show CapybaraCustomizationPreview;
import '../../widgets/home_hero_scene.dart';
import '../../widgets/home_chrome.dart';
import '../../widgets/race_opportunity_card.dart';
import '../../widgets/race_ui.dart';
import '../../widgets/team_scoreline.dart';
import '../display_name_screen.dart';
import '../discoverable_identity_flow.dart';
import '../public_races_screen.dart';
import '../get_coins_screen.dart';
import '../referral_screen.dart';
import '../giveaway_screen.dart';

// Shared hard-offset "game piece" shadow for home cards — flat, no blur, so
// cards read as chunky physical tiles sitting on the dark felt.
const _homeCardShadow = [
  BoxShadow(color: Color(0x66000000), offset: Offset(0, 4), blurRadius: 0),
];

class HomeTab extends StatelessWidget {
  final StepData? stepData;
  final Loadable<StepData>? stepDataState;
  final bool isLoading;
  final String? error;
  final bool healthAuthorized;
  final bool? notificationsState;
  final String? displayName;
  final AuthService authService;
  final BackendApiService backendApiService;
  final ExtraSpinAdController? getCoinsAdController;
  final ExtraSpinAdController? dailyRewardAdController;
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
  final VoidCallback? onOpenProfile;
  final int unreadNotificationCount;
  final VoidCallback? onOpenNotifications;

  /// Jumps to the Friends tab — the SETUP board's "add your first friend" row.
  final VoidCallback? onOpenFriendsTab;
  final VoidCallback? onOpenShop;
  final Future<void> Function()? onAddProfilePhoto;
  final Future<bool> Function()? onDismissProfilePhotoPrompt;
  final Map<String, dynamic>? raceCard;
  final bool raceCardLoading;
  final Loadable<List<HomeRaceSuggestion>> suggestedRacesState;
  final Set<String> joiningSuggestionKeys;
  final Future<void> Function(HomeRaceSuggestion suggestion)? onJoinSuggestion;
  final VoidCallback? onRetrySuggestedRaces;
  final VoidCallback? onOpenPublicRaces;
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

  /// Opens a tournament bracket screen. Added for preview-before-joining: a
  /// suggested-race card can be a TOURNAMENT, and its body tap must land on
  /// TournamentDetailScreen, not RaceDetailScreen.
  final void Function(String tournamentId)? onOpenTournament;
  final Future<void> Function(String raceId)? onJoinRaceFromCard;
  final Future<void> Function(String raceId)? onJoinDiscoveredRace;
  final Future<void> Function(String raceId)? onAcceptRaceInvite;
  final Future<void> Function(String raceId)? onDeclineRaceInvite;
  final void Function(String friendUserId)? onChallengeFriendBack;
  // Lets the shell patch its cached race-card batch when today's daily reward
  // is claimed, so remounting home doesn't show a stale CLAIM button.
  final VoidCallback? onDailyRewardClaimed;
  final bool isTutorialPreview;
  final bool showInviteCodePrompt;
  final VoidCallback? onEnterInviteCode;
  final VoidCallback? onSkipInviteCode;
  final VoidCallback? onStartQuickRace;
  // Shell-owned Inbox state and navigation. Home only presents these values in
  // its hero header; it never fetches or mutates notification data itself.

  /// Shell-owned Home invite overlay is showing this same invitation. Keep the
  /// inline fallback out of the underlying Home tree until it is dismissed.
  final bool suppressPendingInvite;

  const HomeTab({
    super.key,
    required this.stepData,
    this.stepDataState,
    required this.isLoading,
    required this.error,
    required this.healthAuthorized,
    required this.notificationsState,
    required this.displayName,
    required this.authService,
    required this.backendApiService,
    this.getCoinsAdController,
    this.dailyRewardAdController,
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
    this.onOpenProfile,
    this.unreadNotificationCount = 0,
    this.onOpenNotifications,
    this.onOpenFriendsTab,
    this.onOpenShop,
    this.onAddProfilePhoto,
    this.onDismissProfilePhotoPrompt,
    this.raceCard,
    this.raceCardLoading = false,
    this.suggestedRacesState = const Loadable.initial(),
    this.joiningSuggestionKeys = const {},
    this.onJoinSuggestion,
    this.onRetrySuggestedRaces,
    this.onOpenPublicRaces,
    this.streakChipKey,
    this.stepMilestonesKey,
    this.tutorialStepsKey,
    this.tutorialMilestonesKey,
    this.tutorialShopKey,
    this.tutorialFriendsKey,
    this.onOpenRace,
    this.onOpenTournament,
    this.onJoinRaceFromCard,
    this.onJoinDiscoveredRace,
    this.onAcceptRaceInvite,
    this.onDeclineRaceInvite,
    this.onChallengeFriendBack,
    this.onDailyRewardClaimed,
    this.isTutorialPreview = false,
    this.showInviteCodePrompt = false,
    this.onEnterInviteCode,
    this.onSkipInviteCode,
    this.onStartQuickRace,
    this.suppressPendingInvite = false,
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
    final mediaPadding = MediaQuery.of(context).padding;
    final topInset = mediaPadding.top;
    final bottomInset = mediaPadding.bottom;
    final tabBarHeight = 77.5 + bottomInset;
    final bottomPadding = tabBarHeight;
    final hasProfilePhoto =
        authService.profilePhotoUrl != null &&
        authService.profilePhotoUrl!.isNotEmpty;
    final nextRace = isTutorialPreview
        ? null
        : NextRaceState.tryParse(raceCard?['nextRace']);
    final giveawayBanner = _buildGiveawayBanner(context);
    final serviceBanner = giveawayBanner == null
        ? _buildServiceBanner(context)
        : null;

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
                                  8,
                                  16,
                                  0,
                                ),
                                child: _buildQuickActionsRow(context),
                              ),
                            ),
                            // Another person waiting is Home's highest-priority
                            // interruption. Keep it ahead of setup and promotional
                            // notices, but below the user's repeatable daily action.
                            ?_buildPendingInviteSection(),
                            // SETUP follows person-to-person invitations:
                            // finishing it improves every race below, and a user
                            // with no name or photo is worse off in every race
                            // they join. It collapses to a zero-
                            // height SizedBox.shrink when there's nothing to
                            // do, so a finished user sees no gap here.
                            _SetupPromptsSection(
                              compact: _buildPendingInviteSection() != null,
                              displayName: displayName,
                              hasProfilePhoto: hasProfilePhoto,
                              authService: authService,
                              backendApiService: backendApiService,
                              onDisplayNameChanged: onDisplayNameChanged,
                              onAddProfilePhoto: onAddProfilePhoto,
                              onDismissProfilePhotoPrompt:
                                  onDismissProfilePhotoPrompt,
                              showRenameChip:
                                  authService.onboardingV3Enabled &&
                                  !authService.supportsDiscoverableIdentity,
                              // Only an actually-loaded, actually-empty
                              // friends list counts. A null state (tutorial
                              // preview) or an in-flight/failed fetch must
                              // never accuse a user with friends of having
                              // none.
                              hasNoFriends:
                                  friendsStepsState?.isSuccess == true &&
                                  friendsSteps.isEmpty,
                              onFindFriends: onOpenFriendsTab,
                              showInviteCodePrompt:
                                  showInviteCodePrompt && !isTutorialPreview,
                              onEnterInviteCode: onEnterInviteCode,
                              onSkipInviteCode: onSkipInviteCode,
                            ),
                            // Time-bound notices remain reachable, but sit below
                            // direct person-to-person and setup work. They use
                            // compact banner geometry instead of competing with
                            // the primary action above.
                            if (_buildGlobalEventBanner() case final banner?)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  12,
                                  16,
                                  0,
                                ),
                                child: banner,
                              ),
                            if (giveawayBanner case final banner?)
                              Padding(padding: EdgeInsets.zero, child: banner)
                            else if (serviceBanner case final banner?)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  12,
                                  16,
                                  0,
                                ),
                                child: banner,
                              ),
                            if (nextRace?.visible == true)
                              _NextRaceSection(
                                state: nextRace!,
                                shareFirst:
                                    nextRace.createEnabled &&
                                    friendsStepsState?.isSuccess == true &&
                                    friendsSteps.length < 5,
                                onStart: onStartQuickRace,
                                onJoin:
                                    onJoinDiscoveredRace ?? onJoinRaceFromCard,
                                // Row body previews; the "+" still joins.
                                // Null inside the tutorial's fake home so a
                                // tap can never navigate out of it.
                                onPreview:
                                    isTutorialPreview || onOpenRace == null
                                    ? null
                                    : (raceId) => onOpenRace!(raceId),
                              ),
                            // Today's coins sits above the races: it's the one
                            // section that moves every single day whether or not
                            // the user is in a race, so it earns the higher
                            // slot.
                            KeyedSubtree(
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
                            _buildRaceSection(context),
                            _buildFeedbackSection(context),
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
    if (event['active'] != true) return null;

    final endsAtRaw = event['endsAt'];
    final endsAt = endsAtRaw is String
        ? DateTime.tryParse(endsAtRaw)?.toLocal()
        : null;
    if (endsAt == null) return null;
    if (!endsAt.isAfter(DateTime.now())) return null;

    final multiplierRaw = event['multiplier'];
    if (multiplierRaw is! num || !multiplierRaw.isFinite) return null;
    final multiplier = multiplierRaw.toInt();

    return GlobalEventBanner(
      key: const Key('home-global-event-banner'),
      multiplier: multiplier,
      endsAt: endsAt,
      compact: true,
    );
  }

  Widget? _buildServiceBanner(BuildContext context) {
    if (isTutorialPreview) return null;
    final raw = raceCard?['homeServiceBanner'];
    if (raw is! Map || raw['enabled'] != true) return null;
    final message = raw['message'];
    if (message is! String || message.trim().isEmpty || message.length > 240) {
      return null;
    }
    String? contestSlug;
    if (raw.containsKey('action')) {
      final rawAction = raw['action'];
      if (rawAction is! Map || rawAction['type'] != 'contest') return null;
      final slug = rawAction['contestSlug'];
      if (slug is! String ||
          slug.isEmpty ||
          slug.length > 120 ||
          !RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(slug)) {
        return null;
      }
      contestSlug = slug;
    }
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: PixelText.body(
                size: 13,
                color: AppColors.of(context).textDark,
              ),
            ),
          ),
          if (contestSlug != null) ...[
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: AppColors.of(context).textDark,
            ),
          ],
        ],
      ),
    );
    return Container(
      key: const Key('home-service-banner'),
      decoration: BoxDecoration(
        color: AppColors.of(context).parchment,
        border: Border.all(color: AppColors.of(context).coinDark, width: 2),
        borderRadius: BorderRadius.circular(9),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: contestSlug == null
            ? content
            : Semantics(
                button: true,
                label: '$message. Open referral contest details.',
                child: InkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => GiveawayScreen(
                        slug: contestSlug!,
                        authService: authService,
                        backendApiService: backendApiService,
                        equippedAccessories: equippedAccessories,
                        equippedAnimal: equippedAnimal,
                      ),
                    ),
                  ),
                  child: content,
                ),
              ),
      ),
    );
  }

  /// Parses the additive active-contest promotion defensively. The backend
  /// only emits this for one published ACTIVE contest; older servers omit it,
  /// and malformed/expired payloads are ignored so the rest of Home remains
  /// available. A valid result suppresses the legacy service banner above.
  Widget? _buildGiveawayBanner(BuildContext context) {
    if (isTutorialPreview) return null;
    final raw = raceCard?['homeGiveawayBanner'];
    if (raw is! Map) return null;
    if (raw['type'] != 'referral_contest' || raw['status'] != 'ACTIVE') {
      return null;
    }
    final slug = raw['contestSlug'];
    final title = raw['title'];
    final message = raw['message'];
    final endsAtRaw = raw['endsAt'];
    final coinPrize = raw['coinPrize'];
    if (slug is! String ||
        slug.isEmpty ||
        slug.length > 120 ||
        !RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(slug)) {
      return null;
    }
    if (title is! String || title.trim().isEmpty || title.length > 160) {
      return null;
    }
    if (!isValidGlobalGiveawayBannerMessage(message)) return null;
    if (coinPrize is! int || coinPrize <= 0 || coinPrize > 25000) {
      return null;
    }
    if (endsAtRaw is! String) return null;
    final endsAt = DateTime.tryParse(endsAtRaw)?.toLocal();
    if (endsAt == null || !endsAt.isAfter(DateTime.now())) return null;

    return HomeGiveawayBanner(
      message: (message as String).trim(),
      coinPrize: coinPrize,
      endsAt: endsAt,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => GiveawayScreen(
            slug: slug,
            authService: authService,
            backendApiService: backendApiService,
            equippedAccessories: equippedAccessories,
            equippedAnimal: equippedAnimal,
          ),
        ),
      ),
    );
  }

  /// A pending race invite, promoted out of the RACES section to its own block
  /// directly above SETUP (batch 2026-08-10b item 3). Returns null — and so
  /// renders nothing at all, no gap — for every other card state.
  ///
  /// This is a MOVE, not a redesign: it reuses `_buildRaceOpportunityRow`'s
  /// `pendingInvite` branch verbatim, so label/title/subtitle/callbacks are
  /// identical to what RACES used to show.
  ///
  /// Known limitation (accepted): the backend returns exactly one home-card
  /// state, so a user with an ACTIVE race gets `ACTIVE_RACES` and their pending
  /// invite is not in the payload at all. This moves the invite in the case
  /// where it renders today; it does not make invites appear during a race.
  Widget? _buildPendingInviteSection() {
    if (suppressPendingInvite) return null;
    final card = raceCard;
    if (card == null) return null;
    final data = RaceCardData.fromJson(card);
    if (data.state != RaceCardState.pendingInvite) return null;
    return Padding(
      key: const Key('home-pending-invite'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: _buildRaceOpportunityRow(data),
    );
  }

  /// Discovery-only Home rail. Joined races remain authoritative on Races.
  Widget _buildRaceSection(BuildContext context) {
    return ColoredBox(
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _HomeRaceHeader(onViewAll: () => _openPublicRaces(context)),
          _buildSuggestedRacesBody(context),
        ],
      ),
    );
  }

  Widget _buildFeedbackSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: GameContainer(
        key: const Key('home-feedback-card'),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const _SectionTick(),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Found a bug? Have an idea? Let us know',
                    style: PixelText.title(
                      size: 14,
                      color: AppColors.of(context).textDark,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Builder(
              builder: (btnContext) => PillButton(
                key: const Key('home-feedback-button'),
                label: 'SEND FEEDBACK',
                icon: Icons.chat_bubble_outline_rounded,
                variant: PillButtonVariant.secondary,
                fontSize: 13,
                fullWidth: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                onPressed: () => showFeedbackSheet(
                  context: btnContext,
                  authService: authService,
                  backendApiService: backendApiService,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Card-BODY tap target for "preview before joining": opens the race
  /// read-only instead of joining it. The JOIN button on every card keeps its
  /// own direct-join handler untouched.
  ///
  /// Returns null — leaving the card body inert exactly as before this feature
  /// — inside the tutorial's fake home. `tutorial_real_screens.dart` renders
  /// the real [HomeTab] with `isTutorialPreview: true` and no navigation
  /// callbacks; the explicit flag is checked first so a live navigation can
  /// never escape the tutorial even if a callback is wired in later.
  VoidCallback? _previewRaceTap(String raceId) {
    final open = onOpenRace;
    if (isTutorialPreview || open == null || raceId.isEmpty) return null;
    return () => open(raceId);
  }

  /// [_previewRaceTap] for a bracket — suggested-race cards can be tournaments.
  VoidCallback? _previewTournamentTap(String tournamentId) {
    final open = onOpenTournament;
    if (isTutorialPreview || open == null || tournamentId.isEmpty) return null;
    return () => open(tournamentId);
  }

  VoidCallback? _previewSuggestionTap(HomeRaceSuggestion suggestion) =>
      suggestion.kind == HomeRaceSuggestionKind.tournament
      ? _previewTournamentTap(suggestion.id)
      : _previewRaceTap(suggestion.id);

  void _openPublicRaces(BuildContext context) {
    final callback = onOpenPublicRaces;
    if (callback != null) {
      callback();
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PublicRacesScreen(
            authService: authService,
            backendApiService: backendApiService,
          ),
        ),
      );
    }
  }

  Widget _buildSuggestedRacesBody(BuildContext homeContext) {
    final state = suggestedRacesState;
    if (state.shouldShowInitialLoading || state.isInitial) {
      return _buildRaceSkeletonBody();
    }
    final suggestions = state.data;
    if (suggestions != null && suggestions.isNotEmpty) {
      final requestedTextScale =
          MediaQuery.textScalerOf(homeContext).scale(12) / 12;
      final textScale = requestedTextScale < 1 ? 1.0 : requestedTextScale;
      final railHeight = 144.0 + ((textScale - 1) * 96);
      return SizedBox(
        height: railHeight,
        child: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = (constraints.maxWidth * 0.86).clamp(240.0, 300.0);
              // A ListView + PageScrollPhysics used to drive this: that
              // physics always snaps to multiples of the VIEWPORT extent, but
              // each item here is narrower than the viewport (a peeking
              // carousel), so a one-page fling landed the scroll offset
              // between two cards instead of on one.
              // PageController(viewportFraction:) makes each "page" exactly
              // one card + its gutter, so a swipe always settles on a single
              // card.
              const gutter = 18.0;
              final viewportFraction = ((width + gutter) / constraints.maxWidth)
                  .clamp(0.1, 1.0);
              return PageView.builder(
                key: const PageStorageKey('home-suggested-races-carousel'),
                controller: PageController(viewportFraction: viewportFraction),
                padEnds: false,
                itemCount: suggestions.length,
                itemBuilder: (context, index) {
                  final suggestion = suggestions[index];
                  return Padding(
                    padding: const EdgeInsets.only(right: gutter, bottom: 8),
                    child: _HomeSuggestionTicket(
                      key: Key(
                        'home-suggestion-${suggestion.wireKind}-${suggestion.id}',
                      ),
                      suggestion: suggestion,
                      width: width,
                      height: railHeight - 8,
                      joining: joiningSuggestionKeys.contains(
                        suggestion.stableKey,
                      ),
                      onJoin: onJoinSuggestion == null
                          ? null
                          : () => onJoinSuggestion!(suggestion),
                      onPreview: _previewSuggestionTap(suggestion),
                    ),
                  );
                },
              );
            },
          ),
        ),
      );
    }
    return Builder(
      builder: (context) {
        return _HomeSuggestionStatusTicket(
          error: state.isError,
          onPressed: state.isError
              ? (onRetrySuggestedRaces ?? () => onRefresh())
              : () => _openPublicRaces(homeContext),
        );
      },
    );
  }

  /// The board is intentionally a route, not a sixth/hidden shell tab. Keeping
  /// this ticket outside [_buildSuggestedRacesBody] makes its placement stable
  /// across loading, populated, empty, and error suggestion states.
  // Retained as a compatibility helper for older tutorial fixtures; the live
  // home no longer places a leaderboard affordance here.
  // ignore: unused_element
  Widget _buildLeaderboardsTicket(BuildContext context) {
    final colors = AppColors.of(context);
    final callback = isTutorialPreview ? null : onOpenLeaderboardTab;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
      child: Semantics(
        excludeSemantics: true,
        button: true,
        label: "Leaderboards. See today's top walkers",
        onTap: callback ?? () {},
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: const Key('home-leaderboards-ticket'),
            onTap: callback ?? () {},
            excludeFromSemantics: true,
            borderRadius: BorderRadius.circular(12),
            focusColor: colors.coinLight.withValues(alpha: 0.28),
            highlightColor: colors.roofDark.withValues(alpha: 0.12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 68),
              child: Ink(
                padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                decoration: BoxDecoration(
                  color: colors.parchment,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.roofDark, width: 2),
                  boxShadow: _homeCardShadow,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: colors.roofDark,
                        borderRadius: BorderRadius.circular(9),
                        border: Border(
                          top: BorderSide(color: colors.coinLight, width: 2),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.leaderboard_rounded,
                        color: colors.textLight,
                        size: 25,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'LEADERBOARDS',
                            style: PixelText.title(
                              size: 16,
                              color: colors.textDark,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            "See today's top walkers",
                            style: PixelText.body(
                              size: 13,
                              color: colors.textMid,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: colors.textDark,
                      size: 28,
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

  Widget _buildRaceSkeletonBody() {
    return SizedBox(
      height: 170,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
        itemBuilder: (context, index) => _HomeRaceSkeletonTicket(
          key: Key('home-suggestion-skeleton-$index'),
        ),
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemCount: 3,
      ),
    );
  }

  /// Horizontally-scrollable row of [ActiveRaceCard]s, one per active race the
  /// user is in. Driven by the opt-in `ACTIVE_RACES` backend state. Reads the
  /// response defensively (missing/null fields default safely) so a backend on
  /// a different version can't crash the row.
  // Kept as a compatibility renderer while frozen /home/race-card clients and
  // its serializers remain supported; Home discovery no longer calls it. It is
  // public so the complete legacy surface remains pumpable in compatibility
  // tests even though it is no longer part of the live Home composition.
  Widget buildLegacyActiveRacesRow(Map<String, dynamic> cardData) {
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
          final placementPrivacyKnown = race['placementPrivacyActive'] is bool;
          final placementPrivacyActive = race['placementPrivacyActive'] == true;
          final top3 = privacySafeHomeTopThree(race);
          final rawPlacement = placementPrivacyActive
              ? race['userDisplayPlacement']
              : (!placementPrivacyKnown ? null : race['userPlacement']);
          final placement =
              rawPlacement is num &&
                  rawPlacement.isFinite &&
                  rawPlacement == rawPlacement.roundToDouble() &&
                  rawPlacement > 0
              ? rawPlacement.toInt()
              : null;
          // participantCount is sent by newer backends; fall back to the
          // raw podium size, not the privacy-suppressed display projection.
          final rawTopThreeCount =
              (race['top3'] as List?)?.whereType<Map>().length ?? 0;
          final participantCount =
              (race['participantCount'] as num?)?.toInt() ?? rawTopThreeCount;
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

  /// [invitePromoted] is true only for the RACES-section fallback row rendered
  /// when a pending invite has been lifted above Today's Coins. It suppresses
  /// the row's invite-friends button so INVITE doesn't appear twice, meaning
  /// two different things, on one screen.
  Widget _buildRaceOpportunityRow(
    RaceCardData data, {
    bool invitePromoted = false,
  }) {
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
          key: const Key('home-race-row-friend-racing'),
          label: 'LIVE',
          title: '${atName(friend?.displayName ?? 'A friend')} is racing',
          subtitle: participants > 0
              ? '$participants racers'
              : 'A race is happening now',
          primaryLabel: isPublicJoinable ? 'JOIN' : 'OPEN',
          // SCOPE GATE: this row renders for ANY friend race, not only public
          // ones. Preview-before-joining covers public races only — a private
          // friend race the viewer has no participant row in still 403s, so
          // giving it a tap target would just be a dead end. Body tap exists
          // ONLY when isPublicJoinable is true; the OPEN button (which jumps
          // to the Races tab) remains the private race's only affordance.
          onCardTap: isPublicJoinable ? _previewRaceTap(raceId) : null,
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
          key: const Key('home-race-row-public'),
          label: 'PUBLIC',
          title: name,
          subtitle:
              '$participantCount racing${endsAt == null ? '' : ' · ${_formatTimeLeft(endsAt)} left'}',
          primaryLabel: 'JOIN',
          // Public by definition, so the body always previews.
          onCardTap: _previewRaceTap(raceId),
          onPrimary: onJoinRaceFromCard == null || raceId.isEmpty
              ? null
              : () => onJoinRaceFromCard!(raceId),
        );
      case RaceCardState.empty:
        return _HomeRaceActionRow(
          label: 'OPEN',
          title: 'Race your friends',
          subtitle: 'Start with friends or find a public race.',
          // BROWSE, not RACES: the section header directly above this row
          // already says RACES, and a button echoing its own header reads as a
          // rendering bug rather than a choice.
          primaryLabel: 'BROWSE',
          // Suppressed when the invite has been promoted above Today's Coins:
          // that card's eyebrow already says INVITE meaning "you were invited",
          // and this button means "invite friends". Same word, two meanings,
          // one screen.
          secondaryLabel: invitePromoted ? null : 'INVITE',
          onPrimary: onOpenRacesTab,
          onSecondary: invitePromoted
              ? null
              : (ctx) {
                  // Open the referral screen so the invite carries the user's real
                  // /r/BARA-<code> link (earns both sides coins), not a bare store URL.
                  Navigator.of(ctx).push(
                    MaterialPageRoute(
                      builder: (_) => ReferralScreen(
                        authService: authService,
                        backendApiService: backendApiService,
                        equippedAccessories: equippedAccessories,
                        equippedAnimal: equippedAnimal,
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
    final mediaPadding = MediaQuery.of(context).padding;
    final topInset = mediaPadding.top;
    final heroHeight = (compact ? 352.0 : 404.0) + topInset;
    const groundHeight = 84.0;
    final capySize = compact ? 126.0 : 148.0;

    final state = stepDataState;
    final truthfulSteps = state?.data ?? stepData;
    final unresolved =
        state?.shouldShowInitialLoading ?? (isLoading && stepData == null);
    final unresolvedError = state?.isError == true && state?.data == null
        ? state?.error
        : error;
    final Widget hud;
    if (unresolved) {
      hud = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          KeyedSubtree(key: tutorialStepsKey, child: const _PixelStepLoader()),
          const SizedBox(height: 8),
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
    } else if (unresolvedError != null && truthfulSteps == null) {
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
            unresolvedError,
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
      final steps = truthfulSteps?.steps ?? 0;
      hud = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          KeyedSubtree(
            key: tutorialStepsKey,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: CountUpText(
                key: const Key('home-step-count'),
                value: steps,
                format: _formatNumber,
                style: PixelText.display(
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
              left: 20 + mediaPadding.left,
              // Leave a dedicated gutter for the mail control so long names
              // truncate before, rather than underneath, the upper-right HUD.
              right: 144 + mediaPadding.right,
              top: topInset + 12,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Keep the identity block focused on the user and balance;
                  // Inbox sits independently in the hero's upper-right corner.
                  final coinMaxWidth = (constraints.maxWidth * 0.38)
                      .clamp(88.0, 136.0)
                      .toDouble();
                  return SizedBox(
                    height: 64,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MediaQuery.withClampedTextScaling(
                          maxScaleFactor: 1.3,
                          child: Text(
                            atName(displayName ?? 'You'),
                            key: const Key('home-username'),
                            maxLines: 1,
                            softWrap: false,
                            style: PixelText.title(
                              size: 24,
                              color: AppColors.of(context).textLight,
                            ).copyWith(shadows: _heroShadows),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 3),
                        SizedBox(
                          key: const Key('home-coin-balance'),
                          width: coinMaxWidth,
                          height: 25,
                          child: FittedBox(
                            alignment: Alignment.centerLeft,
                            fit: BoxFit.scaleDown,
                            child: CoinBalanceBadge(
                              coins: authService.coins,
                              coinSize: 16,
                              // "+" = earn more coins -> the Get Coins hub
                              // (watch an ad, invite friends, daily box).
                              onAddTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => GetCoinsScreen(
                                    authService: authService,
                                    backendApiService: backendApiService,
                                    adController: getCoinsAdController,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Positioned(
              // The sky's sun/moon occupies the far-right corner. Keep this
              // mail affordance just to its left, clear of the artwork's
              // brightest pixels and consistent across both palettes.
              right: 64 + mediaPadding.right,
              top: topInset + 12,
              child: _buildNotificationHudButton(context),
            ),
            Positioned(
              left: 16,
              right: 16,
              // The compact HUD used to begin at +52. The complete 58px
              // button and its 3px shadow now end at +59, so +72 leaves a
              // deliberate 13px gap while retaining clearance above the
              // walking capybara.
              top: topInset + 88,
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
          ],
        ),
      ),
    );
  }

  /// Daily reward and Shop share the first row under the hero.
  double _quickActionFontSize(BuildContext context) =>
      (MediaQuery.sizeOf(context).width * 0.038).clamp(13.0, 14.0).toDouble();

  Widget _buildQuickActionsRow(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SizedBox(
            height: 48,
            child: KeyedSubtree(
              key: const Key('home-daily-reward-button'),
              child: StreakChip(
                key: streakChipKey,
                authService: authService,
                backendApiService: backendApiService,
                compact: true,
                // Fed by the home batch so the CLAIM button lands with everything
                // else; falls back to its own fetch on old backends.
                initialData: raceCard?['dailyReward'] as Map<String, dynamic>?,
                awaitingBatch: raceCardLoading,
                compactFontSize: _quickActionFontSize(context),
                adController: dailyRewardAdController,
                onClaimedToday: onDailyRewardClaimed,
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: SizedBox(
            height: 48,
            child: KeyedSubtree(
              key: tutorialShopKey,
              child: PillButton(
                key: const Key('home-shop-button'),
                label: 'SHOP',
                icon: Icons.storefront_rounded,
                variant: PillButtonVariant.secondary,
                fontSize: _quickActionFontSize(context),
                fullWidth: true,
                padding: EdgeInsets.symmetric(
                  horizontal: MediaQuery.sizeOf(context).width <= 340 ? 4 : 8,
                  vertical: 10,
                ),
                scaleDownContent: false,
                onPressed: onOpenShop,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNotificationHudButton(BuildContext context) {
    final colors = AppColors.of(context);
    final unreadCount = unreadNotificationCount < 0
        ? 0
        : unreadNotificationCount;
    final enabled = onOpenNotifications != null;
    final semanticsLabel = switch (unreadCount) {
      0 => 'Notifications, no unread notifications',
      1 => 'Notifications, 1 unread notification',
      _ => 'Notifications, $unreadCount unread notifications',
    };
    final badgeLabel = unreadCount > 9 ? '9+' : '$unreadCount';
    // This is hero chrome rather than a card: the mail glyph stays white in
    // both themes so it reads consistently against the day/night sky.
    const iconColor = Colors.white;

    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: semanticsLabel,
      onTap: onOpenNotifications,
      child: ExcludeSemantics(
        child: Tooltip(
          message: 'Notifications',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: const Key('home-notifications-card'),
              onTap: onOpenNotifications,
              borderRadius: BorderRadius.circular(22),
              child: Ink(
                key: const Key('home-notifications-backplate'),
                width: 44,
                height: 44,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Center(
                      child: Icon(
                        Icons.mail_outline_rounded,
                        size: 33,
                        color: iconColor,
                        shadows: _heroShadows,
                      ),
                    ),
                    if (unreadCount > 0)
                      Positioned(
                        top: -7,
                        right: -7,
                        child: Container(
                          key: const Key('home-notifications-badge'),
                          constraints: const BoxConstraints(
                            minWidth: 27,
                            minHeight: 27,
                          ),
                          padding: EdgeInsets.symmetric(
                            horizontal: unreadCount > 9 ? 4 : 3,
                          ),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: colors.coinLight,
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(
                              color: colors.textLight,
                              width: 1.5,
                            ),
                          ),
                          child: MediaQuery.withClampedTextScaling(
                            maxScaleFactor: 1,
                            child: Text(
                              badgeLabel,
                              maxLines: 1,
                              style: PixelText.number(
                                size: 13,
                                color: colors.roofDark,
                              ).copyWith(height: 1),
                            ),
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

class _PixelStepLoader extends StatefulWidget {
  const _PixelStepLoader();

  @override
  State<_PixelStepLoader> createState() => _PixelStepLoaderState();
}

class _PixelStepLoaderState extends State<_PixelStepLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = AppColors.of(context).textLight;
    return Semantics(
      label: 'Loading today’s steps',
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final phase = (_controller.value * 3).floor() % 3;
            return SizedBox(
              width: 64,
              height: 32,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var index = 0; index < 3; index++) ...[
                    Container(
                      width: 12,
                      height: index == phase ? 26 : 14,
                      decoration: BoxDecoration(
                        color: color.withValues(
                          alpha: index == phase ? 1 : 0.55,
                        ),
                        border: Border.all(
                          color: AppColors.of(context).textDark,
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.of(context).textDark,
                            offset: const Offset(2, 2),
                          ),
                        ],
                      ),
                    ),
                    if (index != 2) const SizedBox(width: 8),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The SETUP board: one parchment panel carrying every outstanding setup ask,
/// stacked and separated by a hairline rule.
///
/// One board, not one card per prompt. These are all the same kind of thing —
/// a short question with two answers — and a user with a name prompt AND a
/// photo prompt used to see two competing panels with a gap between them.
class _SetupBoard extends StatelessWidget {
  const _SetupBoard({required this.entries, required this.compact});

  final List<_SetupEntry> entries;
  final bool compact;

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
            color: colors.roofDark.withValues(alpha: compact ? 0.18 : 0.4),
            width: compact ? 1 : 2,
          ),
          boxShadow: compact ? const [] : _homeCardShadow,
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
    required this.compact,
    required this.displayName,
    required this.hasProfilePhoto,
    required this.authService,
    required this.backendApiService,
    required this.onDisplayNameChanged,
    this.onAddProfilePhoto,
    this.onDismissProfilePhotoPrompt,
    this.showRenameChip = false,
    this.hasNoFriends = false,
    this.onFindFriends,
    this.showInviteCodePrompt = false,
    this.onEnterInviteCode,
    this.onSkipInviteCode,
  });

  final bool compact;
  final String? displayName;
  final bool hasProfilePhoto;
  final AuthService authService;
  final BackendApiService backendApiService;
  final VoidCallback onDisplayNameChanged;
  final Future<void> Function()? onAddProfilePhoto;
  final Future<bool> Function()? onDismissProfilePhotoPrompt;

  /// The friends list came back and it was empty. Racing alone is the single
  /// biggest reason a new account goes quiet, so an empty roster is setup work
  /// exactly like a missing photo is.
  final bool hasNoFriends;

  /// Opens the Friends tab. Null hides the row (nowhere to send them).
  final VoidCallback? onFindFriends;
  final bool showInviteCodePrompt;
  final VoidCallback? onEnterInviteCode;
  final VoidCallback? onSkipInviteCode;

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

  Future<void> _openDiscoverableIdentityFlow() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => DiscoverableIdentityFlow(
          authService: widget.authService,
          backendApiService: widget.backendApiService,
          initialFirstName: widget.authService.providerFirstName,
          initialLastName: widget.authService.providerLastName,
        ),
      ),
    );
    widget.onDisplayNameChanged();
    if (mounted) setState(() {});
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
    final showDisplayNamePrompt =
        widget.displayName == null &&
        !widget.authService.supportsDiscoverableIdentity;
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
    final showDiscoverableIdentity =
        widget.authService.shouldShowDiscoverableIdentityRemediation;
    final showFriendPrompt =
        widget.hasNoFriends && widget.onFindFriends != null;

    if (!showDisplayNamePrompt &&
        !showProfilePhotoPrompt &&
        !showDismissedConfirmation &&
        !showFriendPrompt &&
        !showDiscoverableIdentity &&
        !showRenameChip &&
        !widget.showInviteCodePrompt) {
      return const SizedBox.shrink();
    }

    final colors = AppColors.of(context);

    // Every SETUP ask is the same shape — icon, question, two answers — so they
    // share one board instead of each floating in its own card. The old mix of
    // a bare pill chip next to a full card read as two unrelated features that
    // happened to land under the same header.
    final entries = <_SetupEntry>[
      if (showDiscoverableIdentity)
        _SetupEntry(
          icon: Icons.person_search_rounded,
          title: 'HELP FRIENDS FIND YOU',
          subtitle:
              'Add the name people know you by. It is only used so friends can find you in Bara.',
          actions: [
            Expanded(
              child: PillButton(
                key: const Key('home-add-discoverable-name'),
                label: 'ADD YOUR NAME',
                variant: PillButtonVariant.secondary,
                fontSize: 13,
                fullWidth: true,
                onPressed: _openDiscoverableIdentityFlow,
              ),
            ),
          ],
        ),
      if (widget.showInviteCodePrompt)
        _SetupEntry(
          icon: Icons.card_giftcard_rounded,
          title: 'Have an invite code?',
          subtitle:
              "If a friend invited you, enter their code. You'll both earn coins after your first qualifying race.",
          actions: [
            Expanded(
              child: PillButton(
                key: const Key('home-enter-invite-code'),
                label: 'ENTER CODE',
                variant: PillButtonVariant.primary,
                fontSize: 13,
                fullWidth: true,
                onPressed: widget.onEnterInviteCode,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: PillButton(
                key: const Key('home-skip-invite-code'),
                label: 'SKIP',
                variant: PillButtonVariant.secondary,
                fontSize: 13,
                fullWidth: true,
                onPressed: widget.onSkipInviteCode,
              ),
            ),
          ],
        ),
      if (showRenameChip)
        _SetupEntry(
          icon: Icons.badge_rounded,
          title: 'Want a different name?',
          subtitle:
              'We picked @${widget.displayName} for you. It is what friends '
              'look for in a race. Keep it, or make it yours.',
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
        if (entries.isNotEmpty)
          _SetupBoard(entries: entries, compact: widget.compact),
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

class _NextRaceSection extends StatefulWidget {
  const _NextRaceSection({
    required this.state,
    required this.shareFirst,
    required this.onStart,
    required this.onJoin,
    this.onPreview,
  });

  final NextRaceState state;
  final bool shareFirst;
  final VoidCallback? onStart;
  final Future<void> Function(String raceId)? onJoin;

  /// Row-body tap: opens the open race read-only (preview before joining). The
  /// "+" icon button keeps joining directly; while it is disabled (join in
  /// flight) its tap falls through to here, which is intended.
  final void Function(String raceId)? onPreview;

  @override
  State<_NextRaceSection> createState() => _NextRaceSectionState();
}

class _NextRaceSectionState extends State<_NextRaceSection> {
  final Set<String> _joiningIds = {};

  Future<void> _join(String id) async {
    final join = widget.onJoin;
    if (join == null || _joiningIds.contains(id)) return;
    setState(() => _joiningIds.add(id));
    try {
      await join(id);
    } finally {
      if (mounted) setState(() => _joiningIds.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final shareFirst = state.createEnabled && widget.shareFirst;
    final rows = state.discoveryEnabled
        ? state.openRaces
        : const <OpenRaceSummary>[];
    return Column(
      key: const Key('home-next-race-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.createEnabled)
          const _HomeSectionHeader(title: 'CREATE A RACE')
        else
          const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GameContainer(
            frameColor: AppColors.of(context).accent,
            surfaceColor: AppColors.of(context).parchmentLight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  state.createEnabled
                      ? shareFirst
                            ? 'RACE WITH YOUR FRIENDS'
                            : 'START YOUR OWN RACE'
                      : 'OPEN RACES',
                  style: HomeText.display(
                    size: 20,
                    color: AppColors.of(context).ink,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  state.createEnabled
                      ? shareFirst
                            ? 'Create a race, then send the link to your friends. Your race starts when someone joins.'
                            : "Pick a length. We'll help find other walkers."
                      : 'Join a public race started by another walker.',
                  style: HomeText.body(
                    size: 13,
                    color: AppColors.of(context).muted,
                  ),
                ),
                if (state.createEnabled) ...[
                  const SizedBox(height: 14),
                  PillButton(
                    key: const Key('home-start-a-race'),
                    label: shareFirst ? 'CREATE & SHARE' : 'START A RACE',
                    icon: Icons.flag_rounded,
                    fullWidth: true,
                    onPressed: widget.onStart,
                  ),
                ],
                if (rows.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  if (state.createEnabled)
                    Text(
                      'OR JOIN ONE',
                      textAlign: TextAlign.center,
                      style: PixelText.body(
                        size: 12,
                        color: AppColors.of(context).textMid,
                      ),
                    ),
                  const SizedBox(height: 6),
                  for (final race in rows)
                    Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: GestureDetector(
                        key: Key('home-next-race-row-${race.id}'),
                        behavior: HitTestBehavior.opaque,
                        onTap: widget.onPreview == null || race.id.isEmpty
                            ? null
                            : () => widget.onPreview!(race.id),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    race.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: PixelText.title(
                                      size: 13,
                                      color: AppColors.of(context).textDark,
                                    ),
                                  ),
                                  Text(
                                    '${race.participantCount} in',
                                    style: PixelText.body(
                                      size: 12,
                                      color: AppColors.of(context).textMid,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              key: Key('home-join-${race.id}'),
                              tooltip: 'Join ${race.name}',
                              onPressed: !_joiningIds.contains(race.id)
                                  ? () => _join(race.id)
                                  : null,
                              icon: _joiningIds.contains(race.id)
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.add_circle_rounded),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ],
            ),
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
            Expanded(
              child: Text(
                'Suggested Races',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PixelText.title(
                  size: 20,
                  color: AppColors.of(context).textLight,
                ).copyWith(shadows: _textShadows),
              ),
            ),
            const SizedBox(width: 8),
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
                      size: 12,
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

class _HomeSuggestionTicket extends StatelessWidget {
  const _HomeSuggestionTicket({
    super.key,
    required this.suggestion,
    required this.width,
    required this.height,
    required this.joining,
    required this.onJoin,
    this.onPreview,
  });

  final HomeRaceSuggestion suggestion;
  final double width;
  final double height;
  final bool joining;
  final VoidCallback? onJoin;

  /// Card-body tap: opens the race/bracket read-only. Null (inert body) in the
  /// tutorial's fake home. A tap on a DISABLED JOIN pill ("JOINING...") falls
  /// through to this handler — intended: the card should stay viewable.
  final VoidCallback? onPreview;

  int get _prizeCoins {
    for (final source in [suggestion.prizePool, suggestion.finishReward]) {
      if (source == null) continue;
      for (final key in const ['coins', 'pool', 'projectedCoins']) {
        final value = source[key];
        if (value is int && value > 0) {
          return value;
        }
      }
    }
    return 0;
  }

  String get _timeLine {
    if (suggestion.kind == HomeRaceSuggestionKind.tournament) {
      final days = suggestion.matchupDurationDays ?? 1;
      return '$days-DAY MATCHUPS';
    }
    final ends = suggestion.endsAt;
    if (ends != null) {
      final left = ends.difference(DateTime.now());
      if (left.inDays > 0) {
        return '${left.inDays}D ${left.inHours.remainder(24)}H LEFT';
      }
      if (left.inHours > 0) return '${left.inHours}H LEFT';
      if (left.inMinutes > 0) return '${left.inMinutes}M LEFT';
      return 'ENDING SOON';
    }
    final days = suggestion.maxDurationDays ?? 1;
    return '$days-DAY RACE';
  }

  String get _populationLine {
    if (suggestion.kind == HomeRaceSuggestionKind.tournament) {
      return '${suggestion.participantCount}/${suggestion.bracketSize ?? 0} IN';
    }
    final cap = suggestion.maxParticipants;
    return cap == null
        ? '${suggestion.participantCount} RACING'
        : '${suggestion.participantCount}/$cap RACING';
  }

  String get _availabilitySemantics {
    final cap = suggestion.kind == HomeRaceSuggestionKind.tournament
        ? suggestion.bracketSize
        : suggestion.maxParticipants;
    return cap == null
        ? '${suggestion.participantCount} participating'
        : '${suggestion.participantCount} of $cap available';
  }

  @override
  Widget build(BuildContext context) {
    final prize = _prizeCoins;
    final team = suggestion.isTeamRace && suggestion.teamSize != null
        ? '${suggestion.teamSize}v${suggestion.teamSize} TEAMS · '
              '${((suggestion.teamSize! * 2) - suggestion.participantCount).clamp(0, suggestion.teamSize! * 2)} '
              '${((suggestion.teamSize! * 2) - suggestion.participantCount) == 1 ? 'SLOT' : 'SLOTS'}'
        : null;
    final semanticCategory = switch (suggestion.eyebrow) {
      'DAILY' => 'Daily',
      'WEEKLY' => 'Weekly',
      'PUBLIC' => 'Public',
      _ => 'Tournament',
    };
    // The card body is now a preview tap target and the pill inside it is the
    // join action, so the old "…, Join {name}" button label no longer
    // describes what a default tap does. One merged node still fronts the card
    // (its subtree is excluded), so it has to name both affordances: the
    // default action is View, and Join lives on the button inside.
    final semanticParts = [
      semanticCategory,
      suggestion.name,
      _availabilitySemantics,
      if (prize > 0) '$prize coin prize',
      if (onPreview != null) 'View ${suggestion.name}',
      'Join ${suggestion.name} button',
    ];
    return Semantics(
      button: true,
      enabled: onPreview != null || (onJoin != null && !joining),
      label: semanticParts.join(', '),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPreview,
        child: ExcludeSemantics(
          child: SizedBox(
            key: Key(
              'home-suggestion-surface-${suggestion.wireKind}-${suggestion.id}',
            ),
            width: width,
            height: height,
            child: DecoratedBox(
              decoration: raceCardDecoration(context),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment:
                      suggestion.kind == HomeRaceSuggestionKind.publicRace
                      ? CrossAxisAlignment.start
                      : CrossAxisAlignment.center,
                  children: [
                    if (suggestion.kind == HomeRaceSuggestionKind.publicRace)
                      Row(
                        key: const Key('home-public-name-line'),
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              suggestion.name.toUpperCase(),
                              textAlign: TextAlign.left,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: PixelText.title(
                                size: 15,
                                color: AppColors.of(context).textDark,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Pill(
                            label: 'PUBLIC',
                            background: AppColors.of(context).pillGreen,
                            foreground: Colors.white,
                            fontSize: 12,
                          ),
                        ],
                      )
                    else ...[
                      Pill(
                        label: suggestion.eyebrow,
                        background: AppColors.of(context).pillGold,
                        fontSize: 12,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        suggestion.name.toUpperCase(),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PixelText.title(
                          size: 16,
                          color: AppColors.of(context).textDark,
                        ),
                      ),
                    ],
                    const SizedBox(height: 3),
                    Text(
                      '$_timeLine · $_populationLine',
                      textAlign:
                          suggestion.kind == HomeRaceSuggestionKind.publicRace
                          ? TextAlign.left
                          : TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PixelText.body(
                        size: 12,
                        color: AppColors.of(context).textMid,
                      ),
                    ),
                    if (team != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        team,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PixelText.title(
                          size: 12,
                          color: AppColors.of(context).successText,
                        ),
                      ),
                    ],
                    if (prize > 0) ...[
                      const SizedBox(height: 3),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CoinGlyph(size: 14),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              '$prize COIN PRIZE',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: PixelText.title(
                                size: 12,
                                color: AppColors.of(context).coinDark,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 6),
                    PillButton(
                      key: Key(
                        'home-suggestion-join-${suggestion.wireKind}-${suggestion.id}',
                      ),
                      label: joining ? 'JOINING...' : 'JOIN',
                      variant: PillButtonVariant.primary,
                      fontSize: 12.5,
                      fullWidth: true,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7,
                      ),
                      onPressed: joining ? null : onJoin,
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

class _HomeSuggestionStatusTicket extends StatelessWidget {
  const _HomeSuggestionStatusTicket({
    required this.error,
    required this.onPressed,
  });

  final bool error;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: GameContainer(
        key: Key(error ? 'home-suggestions-error' : 'home-suggestions-empty'),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  error ? Icons.refresh_rounded : Icons.explore_rounded,
                  color: AppColors.of(context).pillGoldShadow,
                  size: 26,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    error ? 'RACES TOOK A DETOUR' : 'NO SUGGESTED RACES',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: PixelText.title(
                      size: 14,
                      color: AppColors.of(context).textDark,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            PillButton(
              key: const Key('home-suggestions-status-action'),
              label: error ? 'TRY AGAIN' : 'BROWSE ALL',
              variant: PillButtonVariant.secondary,
              fontSize: 13,
              fullWidth: true,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              onPressed: onPressed,
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeRaceSkeletonTicket extends StatelessWidget {
  const _HomeRaceSkeletonTicket({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 168,
      height: 152,
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
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const _SkeletonBar(width: 48, height: 20),
              const SizedBox(height: 10),
              const _SkeletonBar(width: 104, height: 14),
              const SizedBox(height: 6),
              const _SkeletonBar(width: 82, height: 12),
              const SizedBox(height: 12),
              const _SkeletonBar(width: 92, height: 28),
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
                              : PlacementPill(
                                  placement: placement,
                                  fallbackLabel:
                                      race['placementPrivacyActive'] == true
                                      ? '???'
                                      : 'LIVE',
                                ),
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
    super.key,
    required this.label,
    required this.title,
    required this.subtitle,
    required this.primaryLabel,
    this.secondaryLabel,
    this.onPrimary,
    this.onSecondary,
    this.onCardTap,
  });

  final String label;
  final String title;
  final String subtitle;
  final String primaryLabel;
  final String? secondaryLabel;
  final VoidCallback? onPrimary;

  /// Row-BODY tap: opens the race read-only (preview before joining). Only the
  /// states that can actually be previewed pass one — see
  /// `_buildRaceOpportunityRow`, where the friend-racing row supplies it only
  /// for `isPublicJoinable` races (a private friend race would 403). Null
  /// leaves the body inert, exactly as every row behaved before this feature.
  final VoidCallback? onCardTap;
  // Receives the secondary button's own BuildContext so callers (e.g. share)
  // can anchor an iPad popover to the button's rect.
  final void Function(BuildContext)? onSecondary;

  @override
  Widget build(BuildContext context) {
    final row = DecoratedBox(
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
                      size: 12,
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

    if (onCardTap == null) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onCardTap,
      child: row,
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
                size: 12,
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
          Expanded(
            child: FittedBox(
              alignment: Alignment.centerLeft,
              fit: BoxFit.scaleDown,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PixelText.title(
                  size: 20,
                  color: AppColors.of(context).textLight,
                ).copyWith(shadows: _textShadows),
              ),
            ),
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
