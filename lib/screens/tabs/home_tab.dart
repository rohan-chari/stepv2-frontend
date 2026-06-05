import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/loadable.dart';
import '../../styles.dart';
import '../../models/step_data.dart';
import '../../utils/at_name.dart';
import '../../services/auth_service.dart';
import '../../services/backend_api_service.dart';
import '../../widgets/coin_balance_badge.dart';
import '../../widgets/global_event_banner.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/step_milestones_section.dart';
import '../../widgets/streak_chip.dart' show StreakChip, StreakChipState;
import '../../widgets/home_chrome.dart';
import '../../widgets/home_course_track.dart'
    show CapybaraCustomizationPreview;
import '../../widgets/race_opportunity_card.dart';
import '../../widgets/race_ui.dart';
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
  final VoidCallback? onOpenFriendsTab;
  final VoidCallback? onOpenRacesTab;
  final VoidCallback? onOpenLeaderboardTab;
  final VoidCallback? onOpenShop;
  final Future<void> Function()? onAddProfilePhoto;
  final Future<bool> Function()? onDismissProfilePhotoPrompt;
  final Map<String, dynamic>? raceCard;
  final bool raceCardLoading;
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
    this.onOpenFriendsTab,
    this.onOpenRacesTab,
    this.onOpenLeaderboardTab,
    this.onOpenShop,
    this.onAddProfilePhoto,
    this.onDismissProfilePhotoPrompt,
    this.raceCard,
    this.raceCardLoading = false,
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
                      // GLOBAL STEP EVENT — on-brand "2x STEPS" banner shown to
                      // every user while a step-multiplier window is live. The
                      // shared widget self-ticks the countdown and collapses on
                      // its own once the window ends.
                      if (_buildGlobalEventBanner() case final banner?)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                          child: banner,
                        ),
                      if (raceCard != null)
                        _buildRaceSection()
                      else if (raceCardLoading)
                        _buildRaceSkeletonSection(),
                      _SetupPromptsSection(
                        displayName: displayName,
                        hasProfilePhoto: hasProfilePhoto,
                        authService: authService,
                        onDisplayNameChanged: onDisplayNameChanged,
                        onAddProfilePhoto: onAddProfilePhoto,
                        onDismissProfilePhotoPrompt:
                            onDismissProfilePhotoPrompt,
                      ),
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
      color: AppColors.parchment,
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
      color: AppColors.parchment,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _HomeRaceHeader(onViewAll: onOpenRacesTab),
          SizedBox(
            height: 218,
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
      height: 218,
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
              raceName: race['name'] as String? ?? 'Race',
              endsAt: endsAt,
              placement: placement,
              participantCount: participantCount,
              top3: top3,
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
              : () => onDeclineRaceInvite!(raceId),
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
          title: '${atName(friend?.displayName ?? 'A friend')} finished $raceName',
          subtitle: 'Start a rematch when you are ready',
          primaryLabel: 'CHALLENGE',
          onPrimary: onChallengeFriendBack == null || friend == null
              ? null
              : () => onChallengeFriendBack!(friend.userId),
        );
      case RaceCardState.publicRace:
        final raceId = cardData['raceId'] as String? ?? '';
        final name = cardData['name'] as String? ?? 'Public Race';
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
          onSecondary: () {
            Share.share(
              'Race me on Bara — daily step challenges with friends. https://apps.apple.com/us/app/bara-step-challenges/id6760504694',
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
        height: 200,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.parchment,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.roofDark.withValues(alpha: 0.55),
              width: 2,
            ),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 18, 12, 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_rounded, size: 38, color: AppColors.roofMid),
                  const SizedBox(height: 12),
                  Text(
                    'PUBLIC',
                    textAlign: TextAlign.center,
                    style: PixelText.title(size: 17, color: AppColors.textDark),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Find a race',
                    textAlign: TextAlign.center,
                    style: PixelText.body(size: 12, color: AppColors.textMid),
                  ),
                ],
              ),
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
                        atName(displayName ?? 'You'),
                        style: PixelText.title(
                          size: 24,
                          color: AppColors.parchment,
                        ).copyWith(shadows: _heroShadows),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    CoinBalanceBadge(coins: authService.coins, coinSize: 16),
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
          _HomeNoticeRow(
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
          _HomeNoticeRow(
            icon: Icons.add_a_photo_rounded,
            title: 'Add a profile photo?',
            subtitle:
                'Make it easier for friends to spot you in races and leaderboards.',
            actions: [
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

class _HomeNoticeRow extends StatelessWidget {
  const _HomeNoticeRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actions,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.parchmentDark.withValues(alpha: 0.44),
        border: Border(
          top: BorderSide(
            color: AppColors.parchmentBorder.withValues(alpha: 0.72),
          ),
          bottom: BorderSide(
            color: AppColors.parchmentBorder.withValues(alpha: 0.46),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 24, color: AppColors.roofMid),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: PixelText.title(
                          size: 20,
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: PixelText.body(
                          size: 13,
                          color: AppColors.textMid,
                        ),
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
        color: AppColors.parchmentBorder.withValues(alpha: 0.46),
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
        color: AppColors.parchmentBorder.withValues(alpha: 0.46),
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
    final dividerColor = AppColors.parchmentBorder.withValues(alpha: 0.72);
    return Padding(
      padding: EdgeInsets.zero,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 9),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: dividerColor)),
        ),
        child: Row(
          children: [
            Text(
              'RACES',
              style: PixelText.title(
                size: 20,
                color: AppColors.textDark,
              ).copyWith(shadows: _textShadows),
            ),
            const Spacer(),
            if (onViewAll != null)
              GestureDetector(
                onTap: onViewAll,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 6,
                  ),
                  child: Text(
                    'VIEW ALL',
                    style: PixelText.title(size: 12, color: AppColors.textMid),
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
      height: 200,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.parchment.withValues(alpha: 0.96),
          border: Border.all(
            color: AppColors.roofDark.withValues(alpha: 0.18),
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
  });

  final double width;
  final String raceName;
  final DateTime? endsAt;
  final int? placement;
  final int participantCount;
  final List<Map<String, dynamic>> top3;
  final VoidCallback? onTap;

  String _compactTimeLeft(DateTime endsAt) {
    final remaining = endsAt.difference(DateTime.now());
    if (remaining.isNegative) return 'ENDING SOON';
    if (remaining.inDays > 0) return '${remaining.inDays}D LEFT';
    if (remaining.inHours > 0) return '${remaining.inHours}H LEFT';
    if (remaining.inMinutes > 0) return '${remaining.inMinutes}M LEFT';
    return '${remaining.inSeconds}S LEFT';
  }

  @override
  Widget build(BuildContext context) {
    final endsAt = this.endsAt;
    return SizedBox(
      width: width,
      height: 200,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              color: AppColors.parchment,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.roofDark.withValues(alpha: 0.55),
                width: 2,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  PlacementPill(placement: placement),
                  const SizedBox(height: 12),
                  Text(
                    raceName,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: PixelText.title(size: 18, color: AppColors.textDark),
                  ),
                  const Spacer(),
                  RacerAvatarStack(entries: top3),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$participantCount racer${participantCount == 1 ? '' : 's'}',
                        style: PixelText.body(size: 13, color: AppColors.textMid),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: AppColors.textMid,
                      ),
                    ],
                  ),
                  if (endsAt != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      _compactTimeLeft(endsAt),
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: PixelText.body(size: 12, color: AppColors.textMid),
                    ),
                  ],
                ],
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
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.parchment.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.roofDark.withValues(alpha: 0.18)),
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
                    style: PixelText.title(size: 10, color: AppColors.roofMid),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PixelText.title(size: 17, color: AppColors.textDark),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PixelText.body(size: 12, color: AppColors.textMid),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SmallRaceButton(label: primaryLabel, onPressed: onPrimary),
                if (secondaryLabel != null) ...[
                  const SizedBox(height: 6),
                  _SmallRaceButton(
                    label: secondaryLabel!,
                    onPressed: onSecondary,
                    muted: true,
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
            color: muted ? AppColors.parchmentLight : AppColors.pillGold,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: muted ? AppColors.parchmentBorder : AppColors.pillGoldDark,
              width: 1.5,
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PixelText.title(
              size: 10,
              color: muted ? AppColors.textMid : AppColors.textDark,
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
    final dividerColor = AppColors.parchmentBorder.withValues(alpha: 0.72);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 9),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: dividerColor)),
      ),
      child: Text(
        title,
        style: PixelText.title(
          size: 20,
          color: AppColors.textDark,
        ).copyWith(shadows: _textShadows),
      ),
    );
  }
}
