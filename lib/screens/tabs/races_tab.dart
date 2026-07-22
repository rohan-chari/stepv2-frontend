import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/material.dart';

import '../../models/loadable.dart';
import '../../models/race_handoff_result.dart';
import '../../services/auth_service.dart';
import '../../services/backend_api_service.dart';
import '../../services/notification_service.dart';
import '../../styles.dart';
import '../../utils/at_name.dart';
import '../../utils/race_participant_display.dart';
import '../../utils/tournament.dart';
import '../../widgets/arcade_fx.dart';
import '../../widgets/error_toast.dart';
import '../../widgets/featured_race_card.dart';
import '../../widgets/info_toast.dart';
import '../../widgets/loading_skeleton.dart';
import '../../widgets/pill_button.dart';
import '../../utils/team_race.dart';
import '../../widgets/powerup_icon.dart';
import '../../widgets/spinning_coin.dart';
import '../../widgets/spinning_crate.dart';
import '../../widgets/team_scoreline.dart';
import '../../widgets/tournament_game_card.dart';
import '../create_race_screen.dart';
import '../public_races_screen.dart';
import '../race_detail_screen.dart';
import '../tournament_detail_screen.dart';

// Hard-offset "game piece" shadow shared with the home tab's card language.
const _raceCardShadow = [
  BoxShadow(color: Color(0x66000000), offset: Offset(0, 4), blurRadius: 0),
];

class RacesTab extends StatefulWidget {
  final AuthService authService;
  final Map<String, dynamic>? racesData;
  final Loadable<Map<String, dynamic>>? racesState;
  final List<Map<String, dynamic>> friendsSteps;
  final List<Map<String, dynamic>> featuredRaces;
  // D13: featured (seeded) tournaments merged into the same featured row.
  // Defaults to const [] so an older backend / missing key → race-only row.
  final List<Map<String, dynamic>> featuredTournaments;
  final Future<void> Function() onRacesChanged;
  final Future<void> Function()? onRefresh;
  // Joins a featured (seeded) race; returns true on success. The card shows a
  // confirmation toast and flips to VIEW once the refreshed data comes back.
  final Future<bool> Function(String raceId)? onJoinFeaturedRace;
  // D13: joins a featured (seeded) tournament; returns true on success, then the
  // callback opens the lobby. Mirrors [onJoinFeaturedRace].
  final Future<bool> Function(String tournamentId)? onJoinFeaturedTournament;
  // Number of joinable public races (matches PublicRacesScreen's list). Shown
  // inline in the PUBLIC RACES button label. Defaults to 0 until loaded; the
  // parent keeps the last known value on a fetch error.
  final int publicRacesCount;
  final String? displayName;
  final NotificationService? notificationService;
  final VoidCallback? onOpenProfile;
  // Optional tutorial spotlight anchors (null in the shipped app). The tutorial
  // passes keys so its overlay can measure the races header/pot explainer, the
  // first active race row, and that row's queued-powerups chip.
  final GlobalKey? tutorialPotKey;
  final GlobalKey? tutorialCardKey;
  final GlobalKey? tutorialBoxKey;
  // Injected only by tests; production creates its own. Used for the tournament
  // invite accept/decline calls.
  final BackendApiService? backendApiService;

  const RacesTab({
    super.key,
    required this.authService,
    this.racesData,
    this.racesState,
    required this.friendsSteps,
    this.featuredRaces = const [],
    this.featuredTournaments = const [],
    required this.onRacesChanged,
    this.onRefresh,
    this.onJoinFeaturedRace,
    this.onJoinFeaturedTournament,
    this.publicRacesCount = 0,
    this.displayName,
    this.notificationService,
    this.onOpenProfile,
    this.tutorialPotKey,
    this.tutorialCardKey,
    this.tutorialBoxKey,
    this.backendApiService,
  });

  @override
  State<RacesTab> createState() => _RacesTabState();
}

/// D13: the ALL / RACES / TOURNAMENTS filter that lives in the FEATURED
/// section header. It scopes ONLY the featured strip — never the personal list.
enum _ContentFilter { all, races, tournaments }

/// §4.1: the personal-list state filter. Races and tournaments are merged into
/// one list per state; unanswered invites are pinned ABOVE these pills so the
/// most actionable item in the app can never be hidden behind a filter.
enum _PersonalState { active, pending, completed }

extension _PersonalStateLabel on _PersonalState {
  String get label => switch (this) {
    _PersonalState.active => 'ACTIVE',
    _PersonalState.pending => 'PENDING',
    _PersonalState.completed => 'COMPLETED',
  };

  /// State-specific empty copy — an empty list should say which shelf is empty,
  /// and point at the next action rather than just reporting nothing.
  String get emptyMessage => switch (this) {
    _PersonalState.active => 'No races running right now.',
    _PersonalState.pending => 'Nothing waiting to start.',
    _PersonalState.completed => 'No finished races yet.',
  };

  TournamentListState get tournamentState => switch (this) {
    _PersonalState.active => TournamentListState.active,
    _PersonalState.pending => TournamentListState.pending,
    _PersonalState.completed => TournamentListState.completed,
  };
}

/// One row in the merged personal list: either an ordinary race or a
/// tournament. Kept as a tagged wrapper rather than a shared shape so each row
/// builder reads its OWN payload defensively.
class _ListEntry {
  const _ListEntry.race(this.data) : isTournament = false;
  const _ListEntry.tournament(this.data) : isTournament = true;

  final Map<String, dynamic> data;
  final bool isTournament;
}

class _RacesTabState extends State<RacesTab> {
  static const _textShadows = [
    Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  // Guards against double-pushing RaceDetailScreen from rapid taps.
  bool _navigatingToRace = false;
  // D13 featured-strip filter (the personal list is unaffected).
  _ContentFilter _contentFilter = _ContentFilter.all;

  /// §4.1: the selected personal-list state. Always initialised to ACTIVE for a
  /// freshly created state — that's where the actionable races live.
  _PersonalState _selectedState = _PersonalState.active;

  /// Last-known count per state, so a badge for a bucket that hasn't resolved
  /// yet holds its previous value instead of flickering to 0 mid-refresh.
  final Map<_PersonalState, int> _lastCounts = {
    _PersonalState.active: 0,
    _PersonalState.pending: 0,
    _PersonalState.completed: 0,
  };
  // tournamentId being joined from a featured card (shows JOINING… state).
  String? _joiningFeaturedTournamentId;

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

  Future<void> _joinFeaturedTournament(String tournamentId) async {
    final onJoin = widget.onJoinFeaturedTournament;
    if (onJoin == null ||
        tournamentId.isEmpty ||
        _joiningFeaturedTournamentId != null) {
      return;
    }
    setState(() => _joiningFeaturedTournamentId = tournamentId);
    await onJoin(tournamentId);
    if (!mounted) return;
    setState(() => _joiningFeaturedTournamentId = null);
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

  BackendApiService? _lazyApi;
  BackendApiService get _api =>
      widget.backendApiService ?? (_lazyApi ??= BackendApiService());

  // The additive `tournaments` bucket from GET /races (spec §6.3). Absent on an
  // older backend → empty, so there's simply no tournaments section. Read every
  // field defensively via [Tournament].
  List<Map<String, dynamic>> get _tournaments =>
      (_raceData?['tournaments'] as List?)
          ?.whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .where((t) => Tournament.myStatus(t) != 'DECLINED')
          .toList() ??
      const [];

  /// The rest of my brackets (ACCEPTED, or any non-invite state). Still used by
  /// the featured strip's repeat-entry guard.
  List<Map<String, dynamic>> get _myTournaments =>
      _tournaments.where((t) => !Tournament.amInvited(t)).toList();

  /// §4.2: tournaments classified into one personal-list state.
  List<Map<String, dynamic>> _tournamentsIn(TournamentListState state) {
    final userId = widget.authService.userId;
    return _tournaments
        .where((t) => Tournament.personalListState(t, userId: userId) == state)
        .toList();
  }

  /// Unanswered tournament invitations — pinned above the pills (§4.1). Covers
  /// invites to a bracket that already started, which render Decline-only.
  List<Map<String, dynamic>> get _tournamentInvites =>
      _tournamentsIn(TournamentListState.invite);

  /// The merged personal list for one state: ordinary races first (soonest
  /// ending first for ACTIVE), then tournaments in the same state.
  List<_ListEntry> _entriesFor(_PersonalState state) {
    final races = switch (state) {
      _PersonalState.active => _sortByTimeLeft(_active),
      _PersonalState.pending => _waiting,
      _PersonalState.completed => _completed,
    };
    return [
      for (final r in races) _ListEntry.race(r),
      for (final t in _tournamentsIn(state.tournamentState))
        _ListEntry.tournament(t),
    ];
  }

  /// Badge count for a pill. Derived entirely from the already-loaded
  /// `GET /races` payload — no extra requests, and never blocks first paint.
  int _countFor(_PersonalState state) {
    if (!_effectiveRacesState.hasData) return _lastCounts[state] ?? 0;
    final count = _entriesFor(state).length;
    _lastCounts[state] = count;
    return count;
  }

  bool _navigatingToTournament = false;
  String? _respondingTournamentId;

  void _navigateToTournamentDetail(String tournamentId) {
    if (_navigatingToTournament || tournamentId.isEmpty) return;
    _navigatingToTournament = true;
    Navigator.of(context)
        .push<bool>(
          MaterialPageRoute(
            builder: (context) => TournamentDetailScreen(
              authService: widget.authService,
              tournamentId: tournamentId,
              friends: widget.friendsSteps,
            ),
          ),
        )
        .then((_) {
          _navigatingToTournament = false;
          if (mounted) widget.onRacesChanged();
        });
  }

  Future<void> _respondToTournamentInvite(
    String tournamentId,
    bool accept,
  ) async {
    if (_respondingTournamentId != null || tournamentId.isEmpty) return;
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) return;
    setState(() => _respondingTournamentId = tournamentId);
    try {
      await _api.respondToTournamentInvite(
        identityToken: token,
        tournamentId: tournamentId,
        accept: accept,
      );
      if (mounted) {
        showInfoToast(
          context,
          accept ? "You're in the bracket!" : 'Invite declined.',
        );
      }
      await widget.onRacesChanged();
    } on ApiException catch (e) {
      if (mounted) {
        showErrorToast(
          context,
          e.code != null ? tournamentErrorCopy(e.code) : e.message,
        );
      }
    } catch (_) {
      if (mounted) showErrorToast(context, 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _respondingTournamentId = null);
    }
  }

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
        .push<RaceHandoffResult>(
          MaterialPageRoute(
            builder: (context) =>
                PublicRacesScreen(authService: widget.authService),
          ),
        )
        .then((result) async {
          if (result == null || !mounted) return;
          await widget.onRacesChanged();
          if (!mounted) return;
          setState(() {
            _selectedState = result.isActive
                ? _PersonalState.active
                : _PersonalState.pending;
          });
          _navigateToRaceDetail(result.raceId);
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
              notificationService: widget.notificationService,
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
        Positioned.fill(
          child: ColoredBox(
            color: AppColors.of(context).roofLight,
            child: CustomPaint(
              painter: ArcadeCheckerPainter(drawBottomStripe: false),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(top: topInset + 14, bottom: tabBarHeight),
          child: RefreshIndicator(
            onRefresh: widget.onRefresh ?? () async {},
            color: AppColors.of(context).accent,
            backgroundColor: AppColors.of(context).parchment,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              // §9.5: lazily-built slivers. The header/pills/featured block stays
              // one eager adapter (the featured horizontal strip needs a box
              // context and misbehaves as a bare sibling sliver); each EXPANDED
              // race section below builds its rows through a SliverList.builder,
              // so initial build work is bounded by visible rows + cache extent,
              // not total list size. Collapsed sections emit only their header
              // (no child race cards). Visuals, order, keys, and states are
              // unchanged — this is a perf refactor, not a redesign.
              slivers: _buildContentSlivers(),
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

  /// §9.5: the Races content as lazily-built slivers, replacing the former
  /// single `SliverToBoxAdapter` → `Column`. The header/pills/featured block is
  /// ONE eager adapter (the featured horizontal strip needs a box context and
  /// misbehaves as a bare sibling sliver); race sections build their rows lazily.
  List<Widget> _buildContentSlivers() {
    final invites = _invites;
    final tournamentInvites = _tournamentInvites;

    return <Widget>[
      SliverToBoxAdapter(
        child: Column(
          children: [
            _buildRacesHeader(
              activeCount: _countFor(_PersonalState.active),
              inviteCount: invites.length + tournamentInvites.length,
              waitingCount: _countFor(_PersonalState.pending),
              potKey: widget.tutorialPotKey,
            ),
            StaggerIn(index: 1, child: _buildFeaturedSection()),
          ],
        ),
      ),
      ..._personalListSlivers(
        invites: invites,
        tournamentInvites: tournamentInvites,
      ),
      // Preserves the former outer group's bottom padding (was Padding bottom:8).
      const SliverToBoxAdapter(child: SizedBox(height: 8)),
    ];
  }

  /// D13 ALL / RACES / TOURNAMENTS segmented control. Selects which FEATURED
  /// items appear in the row directly below it — the user's own races/brackets
  /// are never affected.
  Widget _buildContentFilterPills() {
    Widget seg(String label, _ContentFilter value, Key key) {
      final selected = _contentFilter == value;
      return Expanded(
        child: GestureDetector(
          key: key,
          onTap: () => setState(() => _contentFilter = value),
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            // Tighter than the personal-state pills: this is a sub-control
            // scoping one strip, not the page's primary navigation.
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              gradient: selected
                  ? LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppColors.of(context).pillGold,
                        AppColors.of(context).pillGoldDark,
                      ],
                    )
                  : null,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: selected
                    ? AppColors.of(context).pillGoldShadow
                    : Colors.transparent,
                width: 2,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: AppColors.of(context).pillGoldShadow,
                        offset: Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PixelText.title(
                size: 10,
                color: selected
                    ? AppColors.of(context).textDark
                    : AppColors.of(context).textLight.withValues(alpha: 0.85),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 9),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: AppColors.of(context).roofDark.withValues(alpha: 0.38),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.of(context).roofDark, width: 1),
        ),
        child: Row(
          children: [
            seg('ALL', _ContentFilter.all, const Key('content-filter-all')),
            const SizedBox(width: 3),
            seg(
              'RACES',
              _ContentFilter.races,
              const Key('content-filter-races'),
            ),
            const SizedBox(width: 3),
            seg(
              'TOURNAMENTS',
              _ContentFilter.tournaments,
              const Key('content-filter-tournaments'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTournamentTicket(
    Map<String, dynamic> t,
    int index, {
    required bool isInvite,
  }) {
    final id = Tournament.id(t) ?? '';
    final name = Tournament.name(t);
    final statusLine = Tournament.ticketStatusLine(t);
    final winnings = Tournament.championWinnings(t);
    final elim = Tournament.myEliminatedInRound(t);
    final isChamp = Tournament.isChampion(t, widget.authService.userId);
    final stripeColor = index.isOdd
        ? AppColors.of(context).parchmentLight
        : AppColors.of(context).parchment;
    final responding = _respondingTournamentId == id;

    Color badgeColor;
    String badgeLabel;
    if (isInvite) {
      badgeLabel = 'INVITE';
      badgeColor = AppColors.of(context).feedGold;
    } else if (isChamp) {
      badgeLabel = 'CHAMPION';
      badgeColor = AppColors.of(context).feedGold;
    } else if (elim != null) {
      badgeLabel = 'OUT';
      badgeColor = AppColors.of(context).textMid;
    } else if (Tournament.isActive(t)) {
      badgeLabel = 'ALIVE';
      badgeColor = AppColors.of(context).successText;
    } else if (Tournament.isPending(t)) {
      badgeLabel = 'LOBBY';
      badgeColor = AppColors.of(context).feedGold;
    } else {
      badgeLabel = '';
      badgeColor = AppColors.of(context).textMid;
    }

    return GestureDetector(
      onTap: () => _navigateToTournamentDetail(id),
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: stripeColor,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PixelText.title(
                      size: 15,
                      color: AppColors.of(context).textDark,
                    ),
                  ),
                ),
                if (badgeLabel.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: badgeColor,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      badgeLabel,
                      style: PixelText.title(
                        size: 9,
                        color: AppColors.of(context).isDark
                            ? AppColors.of(context).woodDarker
                            : badgeColor == AppColors.of(context).feedGold
                            ? AppColors.of(context).textDark
                            : AppColors.of(context).textLight,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    statusLine,
                    style: PixelText.body(
                      size: 12,
                      color: AppColors.of(context).textMid,
                    ),
                  ),
                ),
                if (winnings > 0) ...[
                  Text(
                    '$winnings',
                    style: PixelText.body(
                      size: 12,
                      color: AppColors.of(context).coinDark,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const SpinningCoin(size: 13),
                ],
              ],
            ),
            if (isInvite) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: PillButton(
                      key: Key('tournament-accept-$id'),
                      label: responding ? '…' : 'ACCEPT',
                      variant: PillButtonVariant.primary,
                      fontSize: 13,
                      fullWidth: true,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      onPressed: responding
                          ? null
                          : () => _respondToTournamentInvite(id, true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: PillButton(
                      key: Key('tournament-decline-$id'),
                      label: 'DECLINE',
                      variant: PillButtonVariant.accent,
                      fontSize: 13,
                      fullWidth: true,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      onPressed: responding
                          ? null
                          : () => _respondToTournamentInvite(id, false),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRacesHeader({
    required int activeCount,
    required int inviteCount,
    required int waitingCount,
    GlobalKey? potKey,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.of(context).roofLight,
        border: Border(
          bottom: BorderSide(color: AppColors.of(context).roofDark, width: 1),
        ),
      ),
      child: CustomPaint(
        painter: const ArcadeCheckerPainter(drawBottomStripe: false),
        child: KeyedSubtree(
          key: potKey,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 15, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'RACES',
                  style: PixelText.title(
                    size: 30,
                    color: AppColors.of(context).textLight,
                  ).copyWith(shadows: _textShadows),
                ),
                const SizedBox(height: 5),
                Text(
                  'Race friends, climb the board, and turn daily steps into wins.',
                  style: PixelText.body(
                    size: 15,
                    color: AppColors.of(
                      context,
                    ).textLight.withValues(alpha: 0.92),
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

  // Pinned "Featured" strip — the live seeded daily/weekly races + seeded
  // tournaments. Always shown (even with no personal races) as a discovery
  // hook. Hidden only when the backend returns nothing at all. D13 (revised):
  // the ALL/RACES/TOURNAMENTS pill above selects which featured items appear —
  // ALL shows both, RACES only featured races, TOURNAMENTS only seeded brackets;
  // an empty selection shows a small note so the pill state always reads clearly.
  Widget _buildFeaturedSection() {
    final featured = widget.featuredRaces;
    final featuredTournaments = widget.featuredTournaments;
    // Hidden only when BOTH are empty (older backend, or the seeding gap).
    if (featured.isEmpty && featuredTournaments.isEmpty) {
      return const SizedBox.shrink();
    }

    final showRaces = _contentFilter != _ContentFilter.tournaments;
    final showTournaments = _contentFilter != _ContentFilter.races;

    // Flatten to a card list per the pill. Featured tournaments lead (novel +
    // time-boxed), then each live seeded race followed by its pre-registerable
    // "next" race.
    final cards = <Widget>[];
    if (showTournaments) {
      for (final t in featuredTournaments) {
        cards.add(_buildFeaturedTournamentCard(t));
      }
    }
    if (showRaces) {
      for (final race in featured) {
        cards.add(_buildFeaturedCard(race));
        // Item 5: the featured row no longer shows the upcoming/opt-in "next
        // race" card — auto-join (managed by the gear toggle above) covers the
        // next daily/weekly. The backend still sends `race['upcoming']`; we
        // simply ignore it here (old clients keep rendering it, which is fine).
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
          child: Row(
            children: [
              WobbleBadge(
                child: Icon(
                  Icons.star_rounded,
                  size: 22,
                  color: AppColors.of(context).pillGold,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                'FEATURED',
                style: PixelText.title(
                  size: 22,
                  color: AppColors.of(context).textLight,
                ).copyWith(shadows: _textShadows),
              ),
              const Spacer(),
              // Featured-races settings (auto-join toggle).
              IconButton(
                icon: Icon(
                  Icons.settings_rounded,
                  size: 22,
                  color: AppColors.of(
                    context,
                  ).textLight.withValues(alpha: 0.85),
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                onPressed: _openFeaturedSettings,
              ),
            ],
          ),
        ),
        // §4.1: the ALL / RACES / TOURNAMENTS filter lives INSIDE the Featured
        // section header now. It scopes only the strip below it — as a
        // full-width row above the header it read as a page-level filter while
        // actually doing something much narrower.
        _buildContentFilterPills(),
        if (cards.isEmpty)
          _buildFeaturedEmptyNote()
        else
          SizedBox(
            height: 232,
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

  /// Small in-row note when the selected featured filter has no items, so the
  /// pill state always reads clearly instead of leaving a blank strip.
  Widget _buildFeaturedEmptyNote() {
    final message = _contentFilter == _ContentFilter.tournaments
        ? 'No featured tournaments right now'
        : 'No featured races right now';
    return Container(
      key: const Key('featured-empty-note'),
      height: 64,
      alignment: Alignment.center,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: PixelText.body(
          size: 13,
          color: AppColors.of(context).textLight.withValues(alpha: 0.9),
        ),
      ),
    );
  }

  // Slide-up settings sheet for the featured strip (same pattern as the
  // profile settings sheet). Currently holds only the auto-join toggle.
  Future<void> _openFeaturedSettings() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.of(context).parchment,
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

  /// D13 featured-row card for a seeded tournament. Same width/visual language
  /// as [FeaturedRaceCard] (leads with a badge, name, key stats, one-tap CTA)
  /// but wired to the tournament join/view flow. D12: JOIN is
  /// pre-disabled while I'm still alive in another same-seed bracket.
  Widget _buildFeaturedTournamentCard(Map<String, dynamic> t) {
    final id = Tournament.id(t) ?? '';
    final joined = Tournament.amIn(t);
    final full = Tournament.isFull(t);
    final aliveElsewhere =
        !joined &&
        Tournament.aliveInSeed(_myTournaments, Tournament.seedKind(t));
    final isJoining = _joiningFeaturedTournamentId == id;

    final String label;
    final PillButtonVariant variant;
    final VoidCallback? onPressed;
    var glow = false;
    if (joined) {
      label = 'VIEW';
      variant = PillButtonVariant.secondary;
      onPressed = () => _navigateToTournamentDetail(id);
    } else if (aliveElsewhere) {
      label = 'IN A BRACKET';
      variant = PillButtonVariant.secondary;
      onPressed = null;
    } else if (full) {
      label = 'FULL';
      variant = PillButtonVariant.secondary;
      onPressed = null;
    } else {
      label = isJoining ? 'JOINING…' : 'JOIN';
      variant = AppColors.of(context).isDark
          ? PillButtonVariant.accent
          : PillButtonVariant.primary;
      glow = !isJoining;
      onPressed = isJoining ? null : () => _joinFeaturedTournament(id);
    }

    return TournamentGameCard(
      width: 250,
      name: Tournament.name(t),
      metaLine:
          '${Tournament.sizeSubcopy(Tournament.bracketSize(t))} · '
          '${Tournament.durationSubcopy(Tournament.matchupDurationDays(t))}',
      filledLabel:
          '${Tournament.acceptedCount(t)}/${Tournament.bracketSize(t)} IN',
      prizeLabel: 'CHAMPION WINS',
      prizeValue: Tournament.championPrizeCoins(t),
      ctaKey: Key('featured-tournament-join-$id'),
      ctaLabel: label,
      ctaVariant: variant,
      ctaGlow: glow,
      onPressed: onPressed,
    );
  }

  /// §4.1: the personal list — pinned invites strip, then the state pills, then
  /// exactly ONE state's rows.
  ///
  /// Perf: only the SELECTED state's `SliverList.builder` is emitted, so
  /// switching pills never builds the other states' rows, and rows within a
  /// state still build lazily against the viewport.
  List<Widget> _personalListSlivers({
    required List<Map<String, dynamic>> invites,
    required List<Map<String, dynamic>> tournamentInvites,
  }) {
    final state = _effectiveRacesState;
    if (state.shouldShowInitialLoading) {
      return const [
        SliverToBoxAdapter(
          child: KeyedSubtree(
            key: Key('races-loading-skeleton'),
            child: _RacesLoadingSkeleton(),
          ),
        ),
      ];
    }

    if (state.isError && !state.hasData) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: LoadErrorPanel(
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
            ),
          ),
        ),
      ];
    }

    final totalInvites = invites.length + tournamentInvites.length;

    return <Widget>[
      if (state.isRefreshing)
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: LinearProgressIndicator(
              minHeight: 2,
              color: AppColors.of(context).accent,
              backgroundColor: Colors.transparent,
            ),
          ),
        ),
      // Invites are pinned ABOVE the pills and omitted entirely at zero.
      if (totalInvites > 0) ..._invitesStripSlivers(invites, tournamentInvites),
      SliverToBoxAdapter(child: StaggerIn(index: 1, child: _buildStatePills())),
      ..._selectedStateSlivers(),
    ];
  }

  /// The pinned invites strip: unanswered race and tournament invitations, with
  /// tournament invites keeping their inline Accept/Decline.
  List<Widget> _invitesStripSlivers(
    List<Map<String, dynamic>> raceInvites,
    List<Map<String, dynamic>> tournamentInvites,
  ) {
    final header = SliverToBoxAdapter(
      // Keyed so callers/tests can distinguish the strip's own header from the
      // "INVITES" metric in the page header above it.
      key: const Key('invites-strip-header'),
      child: StaggerIn(
        index: 0,
        child: Padding(
          padding: const EdgeInsets.only(left: 10, right: 10),
          child: Container(
            padding: const EdgeInsets.fromLTRB(2, 12, 2, 8),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 18,
                  decoration: BoxDecoration(
                    color: AppColors.of(context).pillGold,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: AppColors.of(context).pillGoldDark,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'INVITES',
                  style: PixelText.title(
                    size: 20,
                    color: AppColors.of(context).textLight,
                  ).copyWith(shadows: _textShadows),
                ),
                const SizedBox(width: 6),
                _CountBadge(
                  count: raceInvites.length + tournamentInvites.length,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Tournament invites lead: they expire against a bracket that fills up.
    final rows = SliverList.builder(
      itemCount: tournamentInvites.length + raceInvites.length,
      itemBuilder: (context, i) {
        final isTournament = i < tournamentInvites.length;
        final child = isTournament
            ? _buildTournamentTicket(tournamentInvites[i], i, isInvite: true)
            : _buildRaceRow(
                raceInvites[i - tournamentInvites.length],
                i,
                isInvite: true,
              );
        final isLast = i == tournamentInvites.length + raceInvites.length - 1;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            child,
            if (!isLast)
              Container(
                height: 1,
                color: AppColors.of(
                  context,
                ).parchmentBorder.withValues(alpha: 0.9),
              ),
          ],
        );
      },
    );

    return [
      header,
      SliverPadding(
        padding: const EdgeInsets.only(left: 10, right: 10, bottom: 8),
        sliver: DecoratedSliver(
          decoration: BoxDecoration(
            color: AppColors.of(context).parchment,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.of(context).roofDark.withValues(alpha: 0.55),
              width: 2,
            ),
            boxShadow: _raceCardShadow,
          ),
          sliver: rows,
        ),
      ),
    ];
  }

  /// ACTIVE / PENDING / COMPLETED. Always all three, always with a count badge
  /// (including 0) so the shape of the list is legible before tapping.
  Widget _buildStatePills() {
    Widget seg(_PersonalState state) {
      final selected = _selectedState == state;
      final count = _countFor(state);
      return Expanded(
        child: GestureDetector(
          key: Key('personal-state-${state.name}'),
          onTap: () => setState(() => _selectedState = state),
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
            decoration: BoxDecoration(
              gradient: selected
                  ? LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppColors.of(context).pillGold,
                        AppColors.of(context).pillGoldDark,
                      ],
                    )
                  : null,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: selected
                    ? AppColors.of(context).pillGoldShadow
                    : Colors.transparent,
                width: 2,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: AppColors.of(context).pillGoldShadow,
                        offset: Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    state.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PixelText.title(
                      size: 12,
                      color: selected
                          ? AppColors.of(context).textDark
                          : AppColors.of(context).textLight,
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                // B6 — circular min-width badge around the count. `padding`
                // (not a fixed width) + `minWidth` keeps a single digit round
                // while a two-digit count grows sideways without changing the
                // pill height. Selected → dark-on-light; unselected →
                // parchment-on-translucent, mirroring the count's own colors.
                Container(
                  key: Key('personal-state-badge-${state.name}'),
                  constraints: const BoxConstraints(minWidth: 20),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.of(context).parchment.withValues(alpha: 0.9)
                        : Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: selected
                          ? AppColors.of(
                              context,
                            ).pillGoldShadow.withValues(alpha: 0.6)
                          : AppColors.of(
                              context,
                            ).textLight.withValues(alpha: 0.30),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    '$count',
                    key: Key('personal-state-count-${state.name}'),
                    style: PixelText.title(
                      size: 12,
                      color: selected
                          ? AppColors.of(context).textDark
                          : AppColors.of(
                              context,
                            ).textLight.withValues(alpha: 0.75),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.of(context).roofDark.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.of(context).roofDark, width: 1.5),
        ),
        child: Row(
          children: [
            seg(_PersonalState.active),
            const SizedBox(width: 4),
            seg(_PersonalState.pending),
            const SizedBox(width: 4),
            seg(_PersonalState.completed),
          ],
        ),
      ),
    );
  }

  /// Rows for the SELECTED state only — the other states are never built.
  List<Widget> _selectedStateSlivers() {
    final entries = _entriesFor(_selectedState);

    if (entries.isEmpty) {
      // A user with nothing anywhere gets the fuller onboarding nudge; someone
      // whose ACTIVE shelf just happens to be empty gets the terse line.
      final hasNothingAtAll =
          _invites.isEmpty &&
          _tournamentInvites.isEmpty &&
          _PersonalState.values.every((st) => _entriesFor(st).isEmpty);

      return [
        SliverToBoxAdapter(
          key: Key('personal-state-empty-${_selectedState.name}'),
          child: hasNothingAtAll
              ? _buildEmptyState()
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 28,
                      horizontal: 18,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.of(context).parchment,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.of(
                          context,
                        ).roofDark.withValues(alpha: 0.55),
                        width: 2,
                      ),
                      boxShadow: _raceCardShadow,
                    ),
                    child: Text(
                      _selectedState.emptyMessage,
                      textAlign: TextAlign.center,
                      style: PixelText.body(
                        size: 14,
                        color: AppColors.of(context).textMid,
                      ),
                    ),
                  ),
                ),
        ),
      ];
    }

    final rows = SliverList.builder(
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final entry = entries[i];
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (entry.isTournament)
              _buildTournamentRow(entry.data, i)
            else
              _buildRaceRow(
                entry.data,
                i,
                cardKey: i == 0 ? widget.tutorialCardKey : null,
                boxKey: i == 0 ? widget.tutorialBoxKey : null,
              ),
            if (i != entries.length - 1)
              Container(
                height: 1,
                color: AppColors.of(
                  context,
                ).parchmentBorder.withValues(alpha: 0.9),
              ),
          ],
        );
      },
    );

    return [
      SliverPadding(
        padding: const EdgeInsets.only(left: 10, right: 10, bottom: 8),
        sliver: DecoratedSliver(
          decoration: BoxDecoration(
            color: AppColors.of(context).parchment,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.of(context).roofDark.withValues(alpha: 0.55),
              width: 2,
            ),
            boxShadow: _raceCardShadow,
          ),
          sliver: rows,
        ),
      ),
    ];
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      padding: const EdgeInsets.fromLTRB(18, 34, 18, 36),
      decoration: BoxDecoration(
        color: AppColors.of(context).parchment,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.of(context).roofDark.withValues(alpha: 0.55),
          width: 2,
        ),
        boxShadow: _raceCardShadow,
      ),
      child: Column(
        children: [
          Icon(
            Icons.directions_run_rounded,
            size: 48,
            color: AppColors.of(context).roofMid.withValues(alpha: 0.78),
          ),
          const SizedBox(height: 12),
          Text(
            'No races yet',
            style: PixelText.title(
              size: 20,
              color: AppColors.of(context).textDark,
            ).copyWith(shadows: _textShadows),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Start one with friends or jump into a public race.',
            style: PixelText.body(
              size: 14,
              color: AppColors.of(context).textMid,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// §4.3 — a tournament as a row in the merged personal list.
  ///
  /// An ACTIVE row reuses the active-race row's inventory language, reading the
  /// additive `myCurrentMatch` object. Every field is optional: an older
  /// backend (or a partial object) renders empty slots and no countdown rather
  /// than throwing.
  Widget _buildTournamentRow(Map<String, dynamic> t, int index) {
    final id = Tournament.id(t) ?? '';
    final name = Tournament.name(t);
    final match = Tournament.myCurrentMatch(t);
    final liveRaceId = Tournament.liveMatchRaceId(t);
    final isLive = liveRaceId != null || match != null;

    final round = Tournament.currentRound(t);
    final total = Tournament.totalRounds(t);
    final roundLabel = (round > 0 && total > 0)
        ? Tournament.roundLabelFor(Tournament.bracketSize(t), round)
        : 'BRACKET';

    final placement = Tournament.matchPlacement(match);
    final placementHidden = Tournament.matchPlacementHidden(match);
    final endsAt = Tournament.matchEndsAt(match);

    final stripeColor = index.isOdd
        ? AppColors.of(context).parchmentLight
        : AppColors.of(context).parchment;

    // Badge language matches the old bracket ticket so the states stay
    // recognisable after the merge.
    final elim = Tournament.myEliminatedInRound(t);
    final isChamp = Tournament.isChampion(t, widget.authService.userId);
    String badgeLabel;
    Color badgeColor;
    if (isChamp) {
      badgeLabel = 'CHAMPION';
      badgeColor = AppColors.of(context).feedGold;
    } else if (elim != null) {
      badgeLabel = 'OUT';
      badgeColor = AppColors.of(context).textMid;
    } else if (isLive) {
      badgeLabel = 'ALIVE';
      badgeColor = AppColors.of(context).successText;
    } else if (Tournament.isPending(t)) {
      badgeLabel = 'LOBBY';
      badgeColor = AppColors.of(context).feedGold;
    } else if (Tournament.isActive(t)) {
      badgeLabel = 'ALIVE';
      badgeColor = AppColors.of(context).successText;
    } else {
      badgeLabel = '';
      badgeColor = AppColors.of(context).textMid;
    }

    String timeLabel;
    Color timeColor = AppColors.of(context).textMid;
    if (isLive && endsAt != null) {
      final remaining = endsAt.difference(DateTime.now());
      if (remaining.isNegative) {
        timeLabel = 'ending soon';
        timeColor = AppColors.of(context).error;
      } else if (remaining.inDays > 0) {
        timeLabel =
            '${remaining.inDays}d ${remaining.inHours.remainder(24)}h left';
        timeColor = remaining.inDays >= 2
            ? AppColors.of(context).successText
            : AppColors.of(context).feedGold;
      } else if (remaining.inHours > 0) {
        timeLabel =
            '${remaining.inHours}h ${remaining.inMinutes.remainder(60)}m left';
        timeColor = AppColors.of(context).error;
      } else {
        timeLabel = '${remaining.inMinutes}m left';
        timeColor = AppColors.of(context).error;
      }
    } else {
      // No matchup countdown available: fall back to the bracket status line.
      timeLabel = Tournament.ticketStatusLine(t);
    }

    return Material(
      color: stripeColor,
      child: InkWell(
        key: Key('tournament-row-$id'),
        // A live matchup opens the RACE; everything else opens the bracket.
        onTap: id.isEmpty && liveRaceId == null
            ? null
            : () {
                if (liveRaceId != null && liveRaceId.isNotEmpty) {
                  _navigateToRaceDetail(liveRaceId);
                } else {
                  _navigateToTournamentDetail(id);
                }
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            style: PixelText.title(
                              size: 18,
                              color: AppColors.of(context).textDark,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Bracket marker distinguishes a tournament row from an
                        // ordinary race at a glance.
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: TournamentColors.gold.withValues(
                              alpha: 0.30,
                            ),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: TournamentColors.goldDark,
                            ),
                          ),
                          child: Text(
                            roundLabel,
                            style: PixelText.title(
                              size: 9,
                              color: AppColors.of(context).textDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      timeLabel,
                      style: PixelText.body(size: 13, color: timeColor),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    // Live matchup: same 4-slot inventory strip as an active
                    // race. Absent/partial data simply renders empty slots.
                    if (isLive) ...[
                      const SizedBox(height: 4),
                      _buildInventoryRow(
                        Tournament.matchSlotItems(match),
                        Tournament.matchMysteryBoxCount(match),
                        Tournament.matchQueuedBoxCount(match),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (placement != null)
                    _buildMetaChip(
                      '${formatOrdinal(placement)} PLACE',
                      backgroundColor: AppColors.of(context).isDark
                          ? AppColors.of(context).pillGreenDark
                          : AppColors.of(
                              context,
                            ).pillGreenDark.withValues(alpha: 0.16),
                      textColor: AppColors.of(context).isDark
                          ? AppColors.of(context).textLight
                          : AppColors.of(context).pillGreenDark,
                    )
                  else if (placementHidden)
                    _buildMetaChip(
                      '??? PLACE',
                      backgroundColor: AppColors.of(
                        context,
                      ).textMid.withValues(alpha: 0.16),
                      textColor: AppColors.of(context).textMid,
                    ),
                  if (badgeLabel.isNotEmpty) ...[
                    if (placement != null || placementHidden)
                      const SizedBox(height: 4),
                    Text(
                      badgeLabel,
                      style: PixelText.title(size: 12, color: badgeColor),
                      textAlign: TextAlign.right,
                    ),
                  ],
                  // What the bracket pays out — the reason to care about a
                  // finished row at all.
                  if (Tournament.championWinnings(t) > 0) ...[
                    const SizedBox(height: 3),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${Tournament.championWinnings(t)}',
                          style: PixelText.body(
                            size: 12,
                            color: AppColors.of(context).coinDark,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const SpinningCoin(size: 13),
                      ],
                    ),
                  ],
                ],
              ),
            ],
          ),
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

    // TR-806: team-race chrome for list rows. All reads are defensive — an
    // individual race (or an old payload) has none of these fields.
    final isTeamRace = TeamRace.isTeamRace(race);
    final teamSize = TeamRace.teamSize(race);
    final teamTotals = isTeamRace ? TeamRace.listTeamTotals(race) : null;

    String statusLabel;
    Color badgeColor;
    if (isInvite && !isCreator) {
      statusLabel = 'INVITE';
      badgeColor = AppColors.of(context).feedGold;
    } else if (status == 'ACTIVE') {
      statusLabel = 'ACTIVE';
      badgeColor = AppColors.of(context).successText;
    } else if (status == 'COMPLETED') {
      statusLabel = '';
      badgeColor = AppColors.of(context).textMid;
    } else if (status == 'PENDING' && isCreator) {
      statusLabel = 'SETUP';
      badgeColor = AppColors.of(context).feedGold;
    } else {
      statusLabel = status;
      badgeColor = AppColors.of(context).textMid;
    }

    final stripeColor = index.isOdd
        ? AppColors.of(context).parchmentLight
        : AppColors.of(context).parchment;

    String timeLabel;
    // Default (non-active rows show "Xd race") stays muted; active rows get a
    // green→yellow→red urgency color based on how much time is left.
    Color timeColor = AppColors.of(context).textMid;
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
        timeColor = AppColors.of(
          context,
        ).successText; // 2+ days: plenty of time
      } else if (remaining.inDays >= 1) {
        timeColor = AppColors.of(context).feedGold; // 1–2 days: getting close
      } else {
        timeColor = AppColors.of(
          context,
        ).error; // under a day (or ended): urgent
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
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              style: PixelText.title(
                                size: 18,
                                color: AppColors.of(context).textDark,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                          if (isTeamRace && teamSize != null) ...[
                            const SizedBox(width: 6),
                            TeamFormatChip(teamSize: teamSize),
                          ],
                        ],
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
                        // TR-806: mini team scoreline (only when the payload
                        // carries totals — older backends simply omit it).
                        if (teamTotals != null) ...[
                          const SizedBox(height: 4),
                          TeamScoreline(
                            teamAName: TeamRace.teamName(race, RaceTeam.teamA),
                            teamBName: TeamRace.teamName(race, RaceTeam.teamB),
                            teamATotal: teamTotals.$1,
                            teamBTotal: teamTotals.$2,
                            showRope: false,
                          ),
                        ],
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
                            color: AppColors.of(context).textMid,
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
                          backgroundColor: AppColors.of(context).isDark
                              ? AppColors.of(context).pillGreenDark
                              : AppColors.of(
                                  context,
                                ).pillGreenDark.withValues(alpha: 0.16),
                          textColor: AppColors.of(context).isDark
                              ? AppColors.of(context).textLight
                              : AppColors.of(context).pillGreenDark,
                        )
                      else if (myPlacementHidden)
                        _buildMetaChip(
                          '??? PLACE',
                          backgroundColor: AppColors.of(
                            context,
                          ).textMid.withValues(alpha: 0.16),
                          textColor: AppColors.of(context).textMid,
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
                            color: AppColors.of(context).textMid,
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

/// Loading placeholder for the race list. Mirrors the real layout — two
/// titled sections (gold-tick header + count pill + collapse chevron) each
/// over a parchment card of race-row skeletons. The first section stands in
/// for ACTIVE races: its rows carry the 4-slot inventory crate strip. The
/// second stands in for a placement section: its rows carry a trailing chip.
class _RacesLoadingSkeleton extends StatelessWidget {
  const _RacesLoadingSkeleton();

  // Header sits on the arcade-green surface where text is parchment-toned, so
  // its skeleton bars are light rather than the dark on-card tone.
  Widget _header(BuildContext context, {required bool showPill}) {
    final headerTone = AppColors.of(context).textLight.withValues(alpha: 0.5);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 12, 2, 8),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 18,
            decoration: BoxDecoration(
              color: AppColors.of(context).pillGold,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: AppColors.of(context).pillGoldDark),
            ),
          ),
          const SizedBox(width: 8),
          SkeletonLine(width: 132, height: 18, color: headerTone),
          if (showPill) ...[
            const SizedBox(width: 6),
            SkeletonBox(width: 26, height: 20, radius: 10, color: headerTone),
          ],
          const Spacer(),
          SkeletonBox(width: 22, height: 22, radius: 6, color: headerTone),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context, {
    required bool striped,
    required bool withCrate,
  }) {
    return Container(
      color: striped
          ? AppColors.of(context).parchmentLight
          : AppColors.of(context).parchment,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SkeletonLine(width: 148, height: 15),
                const SizedBox(height: 6),
                const SkeletonLine(width: 96, height: 11),
                if (withCrate) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      for (var i = 0; i < 4; i++) ...[
                        if (i > 0) const SizedBox(width: 3),
                        const SkeletonBox(width: 18, height: 18, radius: 4),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (!withCrate) ...[
            const SizedBox(width: 10),
            const SkeletonBox(width: 54, height: 22, radius: 11),
          ],
        ],
      ),
    );
  }

  Widget _card(
    BuildContext context, {
    required int rows,
    required bool withCrate,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.of(context).parchment,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.of(context).roofDark.withValues(alpha: 0.55),
          width: 2,
        ),
        boxShadow: _raceCardShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          children: [
            for (var i = 0; i < rows; i++) ...[
              if (i > 0)
                Container(
                  height: 1,
                  color: AppColors.of(
                    context,
                  ).parchmentBorder.withValues(alpha: 0.9),
                ),
              _row(context, striped: i.isOdd, withCrate: withCrate),
            ],
          ],
        ),
      ),
    );
  }

  Widget _section(
    BuildContext context, {
    required bool showPill,
    required int rows,
    required bool withCrate,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 10, right: 10, bottom: 8),
      child: Column(
        children: [
          _header(context, showPill: showPill),
          _card(context, rows: rows, withCrate: withCrate),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LoadingSkeleton(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _section(context, showPill: false, rows: 2, withCrate: true),
          _section(context, showPill: true, rows: 3, withCrate: false),
        ],
      ),
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
          top: BorderSide(
            color: AppColors.of(context).textLight.withValues(alpha: 0.2),
          ),
          bottom: BorderSide(
            color: AppColors.of(context).textLight.withValues(alpha: 0.2),
          ),
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
            style: PixelText.title(
              size: 18,
              color: AppColors.of(context).textLight,
            ),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PixelText.title(
                size: 10,
                color: AppColors.of(context).textLight.withValues(alpha: 0.82),
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
      color: AppColors.of(context).textLight.withValues(alpha: 0.22),
    );
  }
}

/// Small translucent count pill used beside a section title.
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
      ),
      child: Text(
        '$count',
        style: PixelText.title(
          size: 13,
          color: AppColors.of(context).textLight.withValues(alpha: 0.92),
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
            style: PixelText.title(
              size: 18,
              color: AppColors.of(context).textDark,
            ),
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
        color: AppColors.of(context).parchmentLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.of(context).parchmentBorder,
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Auto-join daily & weekly races',
                  style: PixelText.body(
                    size: 13,
                    color: AppColors.of(context).textDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Automatically enters you into each new daily and weekly '
                  'challenge, starting with the next one. Turning this off '
                  'stops future auto-joins but keeps races you already '
                  'entered.',
                  style: PixelText.body(
                    size: 11,
                    color: AppColors.of(context).textMid,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          CupertinoSwitch(
            value: widget.authService.autoJoinFeaturedRaces,
            activeTrackColor: AppColors.of(context).accent,
            onChanged: _toggle,
          ),
        ],
      ),
    );
  }
}
