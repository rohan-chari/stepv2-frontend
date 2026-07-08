import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/material.dart';

import '../../models/loadable.dart';
import '../../services/auth_service.dart';
import '../../styles.dart';
import '../../utils/at_name.dart';
import '../../utils/race_participant_display.dart';
import '../../widgets/featured_race_card.dart';
import '../../widgets/ad_inline_card.dart';
import '../../widgets/info_toast.dart';
import '../../widgets/loading_skeleton.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/powerup_icon.dart';
import '../../widgets/spinning_crate.dart';
import '../create_race_screen.dart';
import '../public_races_screen.dart';
import '../race_detail_screen.dart';

class RacesTab extends StatefulWidget {
  final AuthService authService;
  final Map<String, dynamic>? racesData;
  final Loadable<Map<String, dynamic>>? racesState;
  final List<Map<String, dynamic>> friendsSteps;
  final List<Map<String, dynamic>> featuredRaces;
  final Future<void> Function() onRacesChanged;
  final Future<void> Function()? onRefresh;
  // Joins a featured (seeded) race; returns true on success. The card shows a
  // confirmation toast and flips to VIEW once the refreshed data comes back.
  final Future<bool> Function(String raceId)? onJoinFeaturedRace;
  // Number of joinable public races (matches PublicRacesScreen's list). Shown
  // inline in the PUBLIC RACES button label. Defaults to 0 until loaded; the
  // parent keeps the last known value on a fetch error.
  final int publicRacesCount;
  final String? displayName;
  final VoidCallback? onOpenProfile;
  // Optional tutorial spotlight anchors (null in the shipped app). The tutorial
  // passes keys so its overlay can measure the races header/pot explainer, the
  // first active race row, and that row's queued-powerups chip.
  final GlobalKey? tutorialPotKey;
  final GlobalKey? tutorialCardKey;
  final GlobalKey? tutorialBoxKey;

  const RacesTab({
    super.key,
    required this.authService,
    this.racesData,
    this.racesState,
    required this.friendsSteps,
    this.featuredRaces = const [],
    required this.onRacesChanged,
    this.onRefresh,
    this.onJoinFeaturedRace,
    this.publicRacesCount = 0,
    this.displayName,
    this.onOpenProfile,
    this.tutorialPotKey,
    this.tutorialCardKey,
    this.tutorialBoxKey,
  });

  @override
  State<RacesTab> createState() => _RacesTabState();
}

class _RacesTabState extends State<RacesTab> {
  static const _textShadows = [
    Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  // Completed races default to collapsed; users can expand to view history.
  final Set<String> _collapsedSections = {'completed'};
  // Guards against double-pushing RaceDetailScreen from rapid taps.
  bool _navigatingToRace = false;

  // raceId currently being joined from a featured card (shows JOINING… state).
  String? _joiningFeaturedId;

  Future<void> _joinFeatured(String raceId) async {
    final onJoin = widget.onJoinFeaturedRace;
    if (onJoin == null || raceId.isEmpty || _joiningFeaturedId != null) return;
    setState(() => _joiningFeaturedId = raceId);
    final joined = await onJoin(raceId);
    if (!mounted) return;
    setState(() => _joiningFeaturedId = null);
    if (joined) {
      showInfoToast(context, "You're in!");
    }
  }

  void _toggleSection(String sectionKey) {
    setState(() {
      if (_collapsedSections.contains(sectionKey)) {
        _collapsedSections.remove(sectionKey);
      } else {
        _collapsedSections.add(sectionKey);
      }
    });
  }

  // Declined races are excluded server-side on current backends, but an older
  // backend may still return them — filter defensively so a declined race
  // never shows up (the user opted out; it's dead weight they can't act on).
  List<Map<String, dynamic>> get _active =>
      (_raceData?['active'] as List?)
          ?.cast<Map<String, dynamic>>()
          .where((r) => r['myStatus'] != 'DECLINED')
          .toList() ??
      [];

  List<Map<String, dynamic>> get _invites =>
      (_raceData?['pending'] as List?)
          ?.cast<Map<String, dynamic>>()
          .where((r) => r['myStatus'] == 'INVITED')
          .toList() ??
      [];

  List<Map<String, dynamic>> get _waiting =>
      (_raceData?['pending'] as List?)
          ?.cast<Map<String, dynamic>>()
          .where(
            (r) => r['myStatus'] != 'INVITED' && r['myStatus'] != 'DECLINED',
          )
          .toList() ??
      [];

  List<Map<String, dynamic>> get _completed =>
      (_raceData?['completed'] as List?)?.cast<Map<String, dynamic>>() ?? [];

  Loadable<Map<String, dynamic>> get _effectiveRacesState {
    final state = widget.racesState;
    if (state != null) return state;
    final data = widget.racesData;
    if (data != null) return Loadable.success(data);
    return const Loadable.initial();
  }

  Map<String, dynamic>? get _raceData => _effectiveRacesState.data;

  void _navigateToCreateRace() {
    Navigator.of(context)
        .push<Map<String, dynamic>>(
          MaterialPageRoute(
            builder: (context) =>
                CreateRaceScreen(authService: widget.authService),
          ),
        )
        .then((race) async {
          if (race == null || !mounted) return;
          // Refetch the races list before opening detail so a back-out from
          // detail lands on a fresh list that includes the new race.
          await widget.onRacesChanged();
          if (!mounted) return;
          _navigateToRaceDetail(race['id'] as String);
        });
  }

  void _navigateToPublicRaces() {
    Navigator.of(context)
        .push<bool>(
          MaterialPageRoute(
            builder: (context) =>
                PublicRacesScreen(authService: widget.authService),
          ),
        )
        .then((joined) {
          if (joined == true && mounted) {
            widget.onRacesChanged();
          }
        });
  }

  void _navigateToRaceDetail(String raceId) {
    // Rapid taps during the push transition used to stack duplicate detail
    // screens, each running the full details/progress/chat load.
    if (_navigatingToRace) return;
    _navigatingToRace = true;
    Navigator.of(context)
        .push<bool>(
          MaterialPageRoute(
            builder: (context) => RaceDetailScreen(
              authService: widget.authService,
              raceId: raceId,
              friends: widget.friendsSteps,
            ),
          ),
        )
        .then((_) {
          _navigatingToRace = false;
          if (mounted) widget.onRacesChanged();
        });
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final tabBarHeight = 77.5 + bottomInset;

    return Stack(
      children: [
        const Positioned.fill(
          child: ColoredBox(
            color: AppColors.roofLight,
            child: CustomPaint(
              painter: ArcadeCheckerPainter(drawBottomStripe: false),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(top: topInset + 14, bottom: tabBarHeight),
          child: RefreshIndicator(
            onRefresh: widget.onRefresh ?? () async {},
            color: AppColors.accent,
            backgroundColor: AppColors.parchment,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [SliverToBoxAdapter(child: _buildContent())],
            ),
          ),
        ),
      ],
    );
  }

  // Soonest-ending first, so the races closest to wrapping up sit at the top of
  // the list. Races without a parseable endsAt (shouldn't happen for ACTIVE)
  // sink to the bottom.
  List<Map<String, dynamic>> _sortByTimeLeft(List<Map<String, dynamic>> races) {
    final sorted = races.toList();
    sorted.sort((a, b) {
      final aEnds = DateTime.tryParse(a['endsAt'] as String? ?? '');
      final bEnds = DateTime.tryParse(b['endsAt'] as String? ?? '');
      if (aEnds == null && bEnds == null) return 0;
      if (aEnds == null) return 1;
      if (bEnds == null) return -1;
      return aEnds.compareTo(bEnds);
    });
    return sorted;
  }

  Widget _buildContent() {
    final active = _sortByTimeLeft(_active);
    final invites = _invites;
    final waiting = _waiting;
    final completed = _completed;
    final hasRaces =
        active.isNotEmpty ||
        invites.isNotEmpty ||
        waiting.isNotEmpty ||
        completed.isNotEmpty;

    return Column(
      children: [
        _buildRacesHeader(
          activeCount: active.length,
          inviteCount: invites.length,
          waitingCount: waiting.length,
          potKey: widget.tutorialPotKey,
        ),
        ColoredBox(
          color: AppColors.parchment,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
            child: Column(
              children: [
                _buildFeaturedSection(),
                _buildRaceListState(
                  hasRaces: hasRaces,
                  invites: invites,
                  waiting: waiting,
                  active: active,
                  completed: completed,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRacesHeader({
    required int activeCount,
    required int inviteCount,
    required int waitingCount,
    GlobalKey? potKey,
  }) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.roofLight,
        border: Border(bottom: BorderSide(color: AppColors.roofDark, width: 1)),
      ),
      child: CustomPaint(
        painter: const ArcadeCheckerPainter(drawBottomStripe: false),
        child: KeyedSubtree(
          key: potKey,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'RACES',
                  style: PixelText.title(
                    size: 30,
                    color: AppColors.parchment,
                  ).copyWith(shadows: _textShadows),
                ),
                const SizedBox(height: 5),
                Text(
                  'Race friends, climb the board, and turn daily steps into wins.',
                  style: PixelText.body(
                    size: 15,
                    color: AppColors.parchment.withValues(alpha: 0.92),
                  ),
                ),
                const SizedBox(height: 14),
                _RaceHeaderMetrics(
                  activeCount: activeCount,
                  inviteCount: inviteCount,
                  waitingCount: waitingCount,
                ),
                if (widget.displayName != null) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: PillButton(
                          label: 'NEW RACE',
                          icon: Icons.add_rounded,
                          variant: PillButtonVariant.secondary,
                          fontSize: 13,
                          fullWidth: true,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          onPressed: _navigateToCreateRace,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: PillButton(
                          label: 'PUBLIC RACES (${widget.publicRacesCount})',
                          icon: Icons.travel_explore_rounded,
                          variant: PillButtonVariant.accent,
                          fontSize: 13,
                          fullWidth: true,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          onPressed: _navigateToPublicRaces,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Pinned "Featured" strip — the live seeded daily/weekly races. Always shown
  // (even with no personal races) as a discovery hook. Hidden only when the
  // backend returns nothing (e.g. older backend, or the brief gap between a
  // race ending and the next being seeded).
  Widget _buildFeaturedSection() {
    final featured = widget.featuredRaces;
    if (featured.isEmpty) return const SizedBox.shrink();

    // Flatten to a card list: each live seeded race, immediately followed by its
    // pre-registerable "next" race (when present) so the opt-in card sits right
    // next to the live one.
    final cards = <Widget>[];
    for (final race in featured) {
      cards.add(_buildFeaturedCard(race));
      final upcoming = race['upcoming'] as Map<String, dynamic>?;
      final upcomingId = upcoming?['raceId'] as String?;
      if (upcoming != null && upcomingId != null && upcomingId.isNotEmpty) {
        cards.add(_buildUpcomingCard(race, upcoming));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 14, 10, 9),
          child: Row(
            children: [
              const Icon(
                Icons.star_rounded,
                size: 20,
                color: AppColors.pillGoldDark,
              ),
              const SizedBox(width: 5),
              Text(
                'FEATURED',
                style: PixelText.title(
                  size: 22,
                  color: AppColors.textDark,
                ).copyWith(shadows: _textShadows),
              ),
              const Spacer(),
              // Featured-races settings (auto-join toggle).
              IconButton(
                icon: const Icon(
                  Icons.settings_rounded,
                  size: 22,
                  color: AppColors.textDark,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                onPressed: _openFeaturedSettings,
              ),
            ],
          ),
        ),
        SizedBox(
          height: 226,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            physics: const BouncingScrollPhysics(),
            itemCount: cards.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) => cards[i],
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  // Slide-up settings sheet for the featured strip (same pattern as the
  // profile settings sheet). Currently holds only the auto-join toggle.
  Future<void> _openFeaturedSettings() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.parchment,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) =>
          _FeaturedSettingsSheet(authService: widget.authService),
    );
  }

  Widget _buildFeaturedCard(Map<String, dynamic> race) {
    final raceId = race['raceId'] as String? ?? '';
    final reward = race['finishReward'] as Map<String, dynamic>?;
    return FeaturedRaceCard(
      name: race['name'] as String? ?? 'Race',
      seedKind: race['seedKind'] as String?,
      endsAt: DateTime.tryParse(race['endsAt'] as String? ?? ''),
      participantCount: (race['participantCount'] as num?)?.toInt() ?? 0,
      finishRewardPool: (reward?['pool'] as num?)?.toInt() ?? 0,
      finishRewardPlaces: (reward?['paidPlaces'] as num?)?.toInt() ?? 0,
      isJoined: race['myStatus'] != null,
      isFull: race['isFull'] as bool? ?? false,
      isJoining: _joiningFeaturedId == raceId,
      onJoin: () => _joinFeatured(raceId),
      onView: () => _navigateToRaceDetail(raceId),
    );
  }

  // The pre-registerable "next" race for a seed. Reuses FeaturedRaceCard in its
  // upcoming mode: counts down to scheduledStartAt and the CTA is OPT IN /
  // YOU'RE IN. Opting in joins the PENDING race (allowed server-side); once the
  // race starts at midnight, every opt-in begins together at 0.
  Widget _buildUpcomingCard(
    Map<String, dynamic> race,
    Map<String, dynamic> upcoming,
  ) {
    final raceId = upcoming['raceId'] as String? ?? '';
    final reward = race['finishReward'] as Map<String, dynamic>?;
    return FeaturedRaceCard(
      name: race['name'] as String? ?? 'Race',
      seedKind: race['seedKind'] as String?,
      isUpcoming: true,
      startsAt: DateTime.tryParse(
        upcoming['scheduledStartAt'] as String? ?? '',
      ),
      endsAt: DateTime.tryParse(upcoming['endsAt'] as String? ?? ''),
      participantCount: (upcoming['participantCount'] as num?)?.toInt() ?? 0,
      finishRewardPool: (reward?['pool'] as num?)?.toInt() ?? 0,
      finishRewardPlaces: (reward?['paidPlaces'] as num?)?.toInt() ?? 0,
      isJoined: upcoming['myStatus'] != null,
      isFull: upcoming['isFull'] as bool? ?? false,
      isJoining: _joiningFeaturedId == raceId,
      onJoin: () => _joinFeatured(raceId),
      onView: () => _navigateToRaceDetail(raceId),
    );
  }

  Widget _buildRaceListState({
    required bool hasRaces,
    required List<Map<String, dynamic>> invites,
    required List<Map<String, dynamic>> waiting,
    required List<Map<String, dynamic>> active,
    required List<Map<String, dynamic>> completed,
  }) {
    final state = _effectiveRacesState;
    if (state.shouldShowInitialLoading) {
      return const KeyedSubtree(
        key: Key('races-loading-skeleton'),
        child: Padding(
          padding: EdgeInsets.only(top: 4),
          child: ListSkeleton(itemCount: 4),
        ),
      );
    }

    if (state.isError && !state.hasData) {
      return LoadErrorPanel(
        title: 'Couldn’t load races',
        message: state.error ?? 'Check your connection and try again.',
        onRetry: () {
          final refresh = widget.onRefresh;
          if (refresh != null) {
            refresh();
          } else {
            widget.onRacesChanged();
          }
        },
      );
    }

    if (!hasRaces) return _buildEmptyState();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.isRefreshing)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: LinearProgressIndicator(
              minHeight: 2,
              color: AppColors.accent,
              backgroundColor: Colors.transparent,
            ),
          ),
        if (invites.isNotEmpty)
          _buildRaceSection(
            title: 'INVITES',
            sectionKey: 'invites',
            races: invites,
            isInvite: true,
          ),
        if (waiting.isNotEmpty)
          _buildRaceSection(
            title: 'PENDING',
            sectionKey: 'waiting',
            races: waiting,
          ),
        if (active.isNotEmpty)
          _buildRaceSection(
            title: 'ACTIVE RACES',
            sectionKey: 'active',
            races: active,
            showCount: false,
            firstCardKey: widget.tutorialCardKey,
            firstBoxKey: widget.tutorialBoxKey,
            showInFeedAd: true,
          ),
        if (completed.isNotEmpty)
          _buildRaceSection(
            title: 'COMPLETED',
            sectionKey: 'completed',
            races: completed,
            showCount: false,
          ),
      ],
    );
  }

  Widget _buildRaceSection({
    required String title,
    required String sectionKey,
    required List<Map<String, dynamic>> races,
    bool isInvite = false,
    bool showCount = true,
    GlobalKey? firstCardKey,
    GlobalKey? firstBoxKey,
    bool showInFeedAd = false,
  }) {
    final collapsed = _collapsedSections.contains(sectionKey);
    return Padding(
      padding: const EdgeInsets.only(left: 10, right: 10, bottom: 4),
      child: Column(
        children: [
          _buildSectionHeader(
            title,
            races.length,
            sectionKey,
            collapsed,
            showCount: showCount,
          ),
          if (!collapsed)
            _buildRaceList(
              races,
              isInvite: isInvite,
              firstCardKey: firstCardKey,
              firstBoxKey: firstBoxKey,
              showInFeedAd: showInFeedAd,
            ),
        ],
      ),
    );
  }

  Widget _buildRaceList(
    List<Map<String, dynamic>> races, {
    bool isInvite = false,
    GlobalKey? firstCardKey,
    GlobalKey? firstBoxKey,
    bool showInFeedAd = false,
  }) {
    // Single in-feed ad for the section: after the 4th row on longer lists so
    // it reads as part of the feed, else after the last row. The card
    // collapses to zero size unless banners are enabled AND an ad loads, so
    // rows and dividers are untouched in the adless case.
    final adAfterIndex = showInFeedAd
        ? (races.length > 4 ? 3 : races.length - 1)
        : -1;
    return Column(
      children: [
        for (int i = 0; i < races.length; i++) ...[
          _buildRaceRow(
            races[i],
            i,
            isInvite: isInvite,
            cardKey: i == 0 ? firstCardKey : null,
            boxKey: i == 0 ? firstBoxKey : null,
          ),
          if (i == adAfterIndex)
            const AdInlineCard(key: Key('active-section-ad')),
          if (i != races.length - 1)
            Container(
              height: 1,
              color: AppColors.parchmentBorder.withValues(alpha: 0.9),
            ),
        ],
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      padding: const EdgeInsets.fromLTRB(18, 34, 18, 36),
      decoration: BoxDecoration(
        color: AppColors.parchmentDark.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(
            Icons.directions_run_rounded,
            size: 48,
            color: AppColors.roofMid.withValues(alpha: 0.78),
          ),
          const SizedBox(height: 12),
          Text(
            'No races yet',
            style: PixelText.title(
              size: 20,
              color: AppColors.textDark,
            ).copyWith(shadows: _textShadows),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Start one with friends or jump into a public race.',
            style: PixelText.body(size: 14, color: AppColors.textMid),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    String title,
    int count,
    String sectionKey,
    bool collapsed, {
    bool showCount = true,
  }) {
    return GestureDetector(
      onTap: () => _toggleSection(sectionKey),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 14, 10, 7),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: AppColors.parchmentBorder.withValues(alpha: 0.72),
            ),
          ),
        ),
        child: Row(
          children: [
            Text(
              title,
              style: PixelText.title(
                size: 22,
                color: AppColors.textDark,
              ).copyWith(shadows: _textShadows),
            ),
            if (showCount) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: AppColors.parchmentBorder.withValues(alpha: 0.9),
                  ),
                ),
                child: Text(
                  '$count',
                  style: PixelText.title(size: 13, color: AppColors.textMid),
                ),
              ),
            ],
            const Spacer(),
            _SectionToggleButton(
              key: Key('race-section-toggle-$sectionKey'),
              collapsed: collapsed,
              onTap: () => _toggleSection(sectionKey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRaceRow(
    Map<String, dynamic> race,
    int index, {
    bool isInvite = false,
    GlobalKey? cardKey,
    GlobalKey? boxKey,
  }) {
    final raceId = race['id'] as String? ?? '';
    final name = race['name'] as String? ?? 'Race';
    final maxDurationDays = race['maxDurationDays'] as int? ?? 7;
    final endsAt = DateTime.tryParse(race['endsAt'] as String? ?? '');
    final participantCount = race['participantCount'] as int? ?? 0;
    final status = race['status'] as String? ?? '';
    final creator = race['creator'] as Map<String, dynamic>?;
    final creatorName = creator?['displayName'] as String? ?? '';
    final isCreator = race['isCreator'] as bool? ?? false;
    final myPlacement = race['myPlacement'] as int?;
    // Detour Sign: the backend nulls myPlacement and sets this additive flag
    // so the list shows "???" instead of a placement (matches the race-detail
    // masking). Absent on older backends -> false.
    final myPlacementHidden = race['myPlacementHidden'] as bool? ?? false;
    final queuedBoxCount = (race['queuedBoxCount'] as num?)?.toInt() ?? 0;
    // Held/openable mystery boxes for the current user in this race (0..4).
    // Absent on older backends -> defaults to 0.
    final mysteryBoxCount = (race['mysteryBoxCount'] as num?)?.toInt() ?? 0;
    // Per-slot inventory ({type, status, ...}): HELD powerups render as their
    // sprite, MYSTERY_BOX as a crate. Absent on older backends -> falls back to
    // mysteryBoxCount crates.
    final slotItems =
        (race['slotItems'] as List?)?.whereType<Map>().toList() ?? const [];

    String statusLabel;
    Color badgeColor;
    if (isInvite && !isCreator) {
      statusLabel = 'INVITE';
      badgeColor = AppColors.pillGoldDark;
    } else if (status == 'ACTIVE') {
      statusLabel = 'ACTIVE';
      badgeColor = AppColors.pillGreenDark;
    } else if (status == 'COMPLETED') {
      statusLabel = '';
      badgeColor = AppColors.textMid;
    } else if (status == 'PENDING' && isCreator) {
      statusLabel = 'SETUP';
      badgeColor = AppColors.pillGoldDark;
    } else {
      statusLabel = status;
      badgeColor = AppColors.textMid;
    }

    final stripeColor = index.isOdd
        ? AppColors.parchmentLight
        : AppColors.parchment;

    String timeLabel;
    // Default (non-active rows show "Xd race") stays muted; active rows get a
    // green→yellow→red urgency color based on how much time is left.
    Color timeColor = AppColors.textMid;
    if (status == 'ACTIVE' && endsAt != null) {
      final remaining = endsAt.difference(DateTime.now());
      if (remaining.isNegative) {
        timeLabel = 'ending soon';
      } else if (remaining.inDays > 0) {
        timeLabel =
            '${remaining.inDays}d ${remaining.inHours.remainder(24)}h left';
      } else if (remaining.inHours > 0) {
        timeLabel =
            '${remaining.inHours}h ${remaining.inMinutes.remainder(60)}m left';
      } else {
        timeLabel = '${remaining.inMinutes}m left';
      }
      if (remaining.inDays >= 2) {
        timeColor = AppColors.pillGreenDark; // 2+ days: plenty of time
      } else if (remaining.inDays >= 1) {
        timeColor = AppColors.pillGoldShadow; // 1–2 days: getting close
      } else {
        timeColor = AppColors.error; // under a day (or ended): urgent
      }
    } else {
      timeLabel = '${maxDurationDays}d race';
    }

    final showTrailingStatus =
        status != 'ACTIVE' && status != 'COMPLETED' && statusLabel.isNotEmpty;
    final showTrailingContent =
        myPlacement != null || myPlacementHidden || showTrailingStatus;

    return KeyedSubtree(
      key: cardKey,
      child: Material(
        color: stripeColor,
        child: InkWell(
          onTap: raceId.isEmpty ? null : () => _navigateToRaceDetail(raceId),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Row(
              key: Key('race-card-header-$raceId'),
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: PixelText.title(
                          size: 18,
                          color: AppColors.textDark,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      const SizedBox(height: 3),
                      // Active races show time-left then the user's race inventory
                      // (4 slots: held powerup sprites, mystery-box crates, then
                      // queued crates, then empty). Everything else keeps the
                      // runner count.
                      if (status == 'ACTIVE') ...[
                        Text(
                          timeLabel,
                          style: PixelText.body(size: 13, color: timeColor),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                        const SizedBox(height: 4),
                        _buildInventoryRow(
                          slotItems,
                          mysteryBoxCount,
                          queuedBoxCount,
                          rowKey: boxKey,
                        ),
                      ] else
                        Text(
                          '$participantCount runner${participantCount == 1 ? '' : 's'}${isInvite && creatorName.isNotEmpty ? ' \u2022 by ${atName(creatorName)}' : ''}',
                          style: PixelText.body(
                            size: 14,
                            color: AppColors.textMid,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                    ],
                  ),
                ),
                if (showTrailingContent) ...[
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (myPlacement != null)
                        _buildMetaChip(
                          '${formatOrdinal(myPlacement)} PLACE',
                          backgroundColor: AppColors.pillGreenDark.withValues(
                            alpha: 0.16,
                          ),
                          textColor: AppColors.pillGreenDark,
                        )
                      else if (myPlacementHidden)
                        _buildMetaChip(
                          '??? PLACE',
                          backgroundColor: AppColors.textMid.withValues(
                            alpha: 0.16,
                          ),
                          textColor: AppColors.textMid,
                        ),
                      if (showTrailingStatus) ...[
                        if (myPlacement != null || myPlacementHidden)
                          const SizedBox(height: 4),
                        Text(
                          statusLabel,
                          style: PixelText.title(size: 12, color: badgeColor),
                          textAlign: TextAlign.right,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          timeLabel,
                          style: PixelText.body(
                            size: 12,
                            color: AppColors.textMid,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Shows four slots: three active-inventory spots followed by one queue spot,
  // all evenly spaced.
  //   • Active spots fill from [slotItems] — a powerup sprite for HELD items, a
  //     crate for unopened MYSTERY_BOX items — then pad with faded silhouettes.
  //   • The 4th spot is a plain filled crate when [queuedBoxCount] > 0 (a box
  //     earned but waiting because the active inventory is full), else a faded
  //     slot. It renders like a regular box (no dimmed clock-badge variant).
  // [slotItems] is absent on older backends; we then fall back to filling the
  // active spots from [mysteryBoxCount] so the row still reads correctly.
  Widget _buildInventoryRow(
    List slotItems,
    int mysteryBoxCount,
    int queuedBoxCount, {
    GlobalKey? rowKey,
  }) {
    const activeSlots = 3;
    const slotSize = 18.0;
    final active = <Widget>[];

    if (slotItems.isNotEmpty) {
      for (final raw in slotItems) {
        if (active.length >= activeSlots) break;
        final item = raw as Map;
        final status = item['status'] as String?;
        final type = item['type'] as String?;
        if (status == 'HELD' && type != null && type.isNotEmpty) {
          active.add(PowerupIcon(type: type, size: slotSize));
        } else {
          active.add(const CrateIcon(size: slotSize, filled: true));
        }
      }
    } else {
      // Old backend: no per-slot data, just the held mystery-box count.
      for (var i = 0; i < mysteryBoxCount && active.length < activeSlots; i++) {
        active.add(const CrateIcon(size: slotSize, filled: true));
      }
    }
    while (active.length < activeSlots) {
      active.add(const CrateIcon(size: slotSize, filled: false));
    }

    // The queue spot renders as a plain crate — filled when a box is queued,
    // faded when empty — so it reads like any other inventory box (no dimmed
    // clock-badge variant).
    final queueSlot = CrateIcon(size: slotSize, filled: queuedBoxCount > 0);

    return SizedBox(
      key: rowKey,
      height: 20,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < active.length; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            active[i],
          ],
          // Same 3px gap as the inter-slot gaps so the queue spot sits flush
          // with the active inventory.
          const SizedBox(width: 3),
          queueSlot,
        ],
      ),
    );
  }

  Widget _buildMetaChip(
    String label, {
    required Color backgroundColor,
    required Color textColor,
    GlobalKey? chipKey,
  }) {
    return Container(
      key: chipKey,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: PixelText.title(size: 11, color: textColor)),
    );
  }
}

class _RaceHeaderMetrics extends StatelessWidget {
  const _RaceHeaderMetrics({
    required this.activeCount,
    required this.inviteCount,
    required this.waitingCount,
  });

  final int activeCount;
  final int inviteCount;
  final int waitingCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.parchment.withValues(alpha: 0.2)),
          bottom: BorderSide(color: AppColors.parchment.withValues(alpha: 0.2)),
        ),
      ),
      child: Row(
        children: [
          _RaceMetricText(label: 'ACTIVE', count: activeCount),
          _MetricDivider(),
          _RaceMetricText(label: 'INVITES', count: inviteCount),
          _MetricDivider(),
          _RaceMetricText(label: 'PENDING', count: waitingCount),
        ],
      ),
    );
  }
}

class _RaceMetricText extends StatelessWidget {
  const _RaceMetricText({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$count',
            style: PixelText.title(size: 18, color: AppColors.parchment),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PixelText.title(
                size: 10,
                color: AppColors.parchment.withValues(alpha: 0.82),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 18,
      color: AppColors.parchment.withValues(alpha: 0.22),
    );
  }
}

class _SectionToggleButton extends StatelessWidget {
  const _SectionToggleButton({
    super.key,
    required this.collapsed,
    required this.onTap,
  });

  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 30,
        height: 30,
        child: Center(
          child: Icon(
            collapsed ? Icons.add_rounded : Icons.remove_rounded,
            size: 20,
            color: AppColors.textMid,
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet with settings for the featured daily/weekly challenges.
/// Mirrors the profile settings sheet's layout.
class _FeaturedSettingsSheet extends StatelessWidget {
  final AuthService authService;

  const _FeaturedSettingsSheet({required this.authService});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'FEATURED RACES',
            style: PixelText.title(size: 18, color: AppColors.textDark),
          ),
          const SizedBox(height: 16),
          _FeaturedAutoJoinToggle(authService: authService),
        ],
      ),
    );
  }
}

/// Apple-settings-style row toggling auto-join for the daily/weekly featured
/// challenges. Listens to [authService] so it reflects the latest value
/// (including a revert if the backend write fails). Same pattern as the
/// profile tab's leaderboard-visibility toggle.
class _FeaturedAutoJoinToggle extends StatefulWidget {
  final AuthService authService;

  const _FeaturedAutoJoinToggle({required this.authService});

  @override
  State<_FeaturedAutoJoinToggle> createState() =>
      _FeaturedAutoJoinToggleState();
}

class _FeaturedAutoJoinToggleState extends State<_FeaturedAutoJoinToggle> {
  void _handleChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    widget.authService.addListener(_handleChanged);
  }

  @override
  void dispose() {
    widget.authService.removeListener(_handleChanged);
    super.dispose();
  }

  Future<void> _toggle(bool value) async {
    await widget.authService.updateFeaturedAutoJoin(value);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.parchmentLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.parchmentBorder, width: 1.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Auto-join daily & weekly races',
                  style: PixelText.body(size: 13, color: AppColors.textDark),
                ),
                const SizedBox(height: 4),
                Text(
                  'Automatically enters you into each new daily and weekly '
                  'challenge, starting with the next one. Turning this off '
                  'stops future auto-joins but keeps races you already '
                  'entered.',
                  style: PixelText.body(size: 11, color: AppColors.textMid),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          CupertinoSwitch(
            value: widget.authService.autoJoinFeaturedRaces,
            activeTrackColor: AppColors.accent,
            onChanged: _toggle,
          ),
        ],
      ),
    );
  }
}
