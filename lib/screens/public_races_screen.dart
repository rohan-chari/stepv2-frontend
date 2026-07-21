import 'package:flutter/material.dart';

import '../models/loadable.dart';
import '../models/race_handoff_result.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import '../utils/at_name.dart';
import '../utils/team_race.dart';
import '../utils/tournament.dart';
import '../widgets/ad_banner_slot.dart';
import '../widgets/arcade_page.dart';
import '../widgets/error_toast.dart';
import '../widgets/info_toast.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/pill_button.dart';
import '../widgets/retro_card.dart';
import '../widgets/team_side_picker.dart';
import '../widgets/tournament_game_card.dart';
import '../widgets/trail_sign.dart';
import 'create_race_screen.dart';
import 'tournament_detail_screen.dart';

class PublicRacesScreen extends StatefulWidget {
  final AuthService authService;
  final BackendApiService backendApiService;

  PublicRacesScreen({
    super.key,
    required this.authService,
    BackendApiService? backendApiService,
  }) : backendApiService = backendApiService ?? BackendApiService();

  @override
  State<PublicRacesScreen> createState() => _PublicRacesScreenState();
}

/// Top-level content switch for the Public Races screen: ALL shows every group;
/// the others narrow to a single group. Same convention as the races-tab pill.
enum _PublicFilter { all, featured, tournaments, races }

class _PublicRacesScreenState extends State<PublicRacesScreen> {
  static const _textShadows = [
    Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  _PublicFilter _filter = _PublicFilter.all;

  bool _loading = true;
  String? _joiningRaceId;
  List<Map<String, dynamic>> _races = const [];
  Loadable<List<Map<String, dynamic>>> _racesState = const Loadable.initial();

  // Tournaments (spec §9). Featured (seeded) brackets pin above; user-created
  // public brackets follow. `_myTournaments` is my GET /races tournaments bucket
  // used only for the D12 same-seed alive check. All best-effort: any endpoint
  // absent on an older backend simply yields no tournament section.
  List<Map<String, dynamic>> _featuredTournaments = const [];
  List<Map<String, dynamic>> _userTournaments = const [];
  List<Map<String, dynamic>> _myTournaments = const [];
  String? _joiningTournamentId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) {
      setState(() {
        _loading = false;
        _racesState = const Loadable.error('Not signed in.');
      });
      return;
    }
    setState(() {
      _loading = true;
      _racesState = _races.isEmpty
          ? const Loadable.loading()
          : Loadable.refreshing(_races);
    });
    // Load tournaments best-effort in parallel — never let a missing/older
    // tournaments endpoint break the public races list.
    _loadTournaments(token);

    try {
      final races = await widget.backendApiService.fetchPublicRaces(
        identityToken: token,
      );
      if (!mounted) return;
      setState(() {
        _races = races;
        _loading = false;
        _racesState = Loadable.success(races);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _racesState = Loadable.error(
          e.toString(),
          data: _races.isEmpty ? null : _races,
        );
      });
      showErrorToast(context, e.toString());
    }
  }

  Future<void> _navigateToCreateRace() async {
    final race = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (context) => CreateRaceScreen(
          authService: widget.authService,
          backendApiService: widget.backendApiService,
        ),
      ),
    );
    if (!mounted || race == null) return;
    final id = race['id'] as String?;
    if (id == null || id.isEmpty) return;
    Navigator.of(context).pop(
      RaceHandoffResult(
        raceId: id,
        status: race['status'] as String? ?? 'PENDING',
        kind: RaceHandoffKind.created,
      ),
    );
  }

  Future<void> _join(Map<String, dynamic> race) async {
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) return;
    final raceId = race['id'] as String;
    final buyIn = (race['buyInAmount'] as int?) ?? 0;
    if (buyIn > 0 && buyIn > widget.authService.coins) {
      showErrorToast(context, 'Not enough gold for this buy-in');
      return;
    }
    if (buyIn > 0) {
      final confirmed = await _confirmRaceBuyIn(buyIn);
      if (confirmed != true || !mounted) return;
    }

    // TR-201: team races need a side before the join call fires.
    String? team;
    if (TeamRace.isTeamRace(race)) {
      team = await showTeamSidePicker(context: context, race: race);
      if (team == null || !mounted) return; // dismissed the sheet
    }

    setState(() => _joiningRaceId = raceId);
    try {
      Map<String, dynamic> result;
      if (team != null) {
        result = await widget.backendApiService.joinPublicRaceOnTeam(
          identityToken: token,
          raceId: raceId,
          team: team,
        );
      } else {
        result = await widget.backendApiService.joinPublicRace(
          identityToken: token,
          raceId: raceId,
        );
      }
      try {
        final user = await widget.backendApiService.fetchMe(
          identityToken: token,
        );
        await widget.authService.updateCoins(
          user['coins'] as int? ?? widget.authService.coins,
        );
        await widget.authService.updateHeldCoins(
          user['heldCoins'] as int? ?? widget.authService.heldCoins,
        );
      } catch (_) {}
      if (!mounted) return;
      final joinedRace = result['race'] as Map<String, dynamic>?;
      Navigator.of(context).pop(
        RaceHandoffResult(
          raceId: raceId,
          status:
              joinedRace?['status'] as String? ??
              race['status'] as String? ??
              'PENDING',
          kind: RaceHandoffKind.joined,
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _joiningRaceId = null);
      // TEAM_FULL / RACE_ALREADY_STARTED / UPDATE_REQUIRED get the playful
      // team-race copy; older backends without codes keep their message.
      showErrorToast(
        context,
        e.code != null ? teamRaceErrorCopy(e.code) : e.message,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _joiningRaceId = null);
      showErrorToast(context, e.toString());
    }
  }

  Future<bool?> _confirmRaceBuyIn(int buyIn) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        child: TrailSign(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$buyIn GOLD BUY-IN',
                style: PixelText.title(size: 18, color: AppColors.textDark),
              ),
              const SizedBox(height: 12),
              Text(
                'Your $buyIn gold is held until the race starts, then moves into the live pot. It returns only if the race is cancelled.',
                textAlign: TextAlign.center,
                style: PixelText.body(size: 13.5, color: AppColors.textMid),
              ),
              const SizedBox(height: 18),
              PillButton(
                label: 'NEVER MIND',
                variant: PillButtonVariant.secondary,
                fullWidth: true,
                onPressed: () => Navigator.of(dialogContext).pop(false),
              ),
              const SizedBox(height: 10),
              PillButton(
                label: 'LOCK IT IN',
                variant: PillButtonVariant.accent,
                fullWidth: true,
                onPressed: () => Navigator.of(dialogContext).pop(true),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadTournaments(String token) async {
    try {
      final res = await widget.backendApiService.fetchPublicTournaments(
        identityToken: token,
      );
      if (!mounted) return;
      setState(() {
        _featuredTournaments =
            (res['featured'] as List?)?.cast<Map<String, dynamic>>() ??
            const [];
        _userTournaments =
            (res['tournaments'] as List?)?.cast<Map<String, dynamic>>() ??
            const [];
      });
    } catch (_) {
      // Older backend / offline → no tournament section.
    }
    // My tournaments bucket (for the D12 same-seed alive check). Best-effort.
    try {
      final racesRes = await widget.backendApiService.fetchRaces(
        identityToken: token,
      );
      if (!mounted) return;
      setState(() {
        _myTournaments =
            (racesRes['tournaments'] as List?)?.cast<Map<String, dynamic>>() ??
            const [];
      });
    } catch (_) {}
  }

  /// Opens the bracket screen for [tournamentId], refreshing on return.
  void _openTournament(String tournamentId) {
    if (tournamentId.isEmpty) return;
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => TournamentDetailScreen(
              authService: widget.authService,
              tournamentId: tournamentId,
            ),
          ),
        )
        .then((_) {
          if (mounted) _load();
        });
  }

  Future<void> _joinTournament(
    Map<String, dynamic> t, {
    required bool featured,
  }) async {
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) return;
    final id = Tournament.id(t) ?? '';
    if (id.isEmpty || _joiningTournamentId != null) return;

    final buyIn = Tournament.buyInAmount(t);
    if (!featured && buyIn > 0) {
      if (buyIn > widget.authService.coins) {
        showErrorToast(context, 'Not enough gold for this buy-in');
        return;
      }
      final ok = await _confirmBuyIn(buyIn);
      if (ok != true) return;
    }

    setState(() => _joiningTournamentId = id);
    try {
      await widget.backendApiService.joinTournament(
        identityToken: token,
        tournamentId: id,
      );
      try {
        final user = await widget.backendApiService.fetchMe(
          identityToken: token,
        );
        await widget.authService.updateCoins(
          user['coins'] as int? ?? widget.authService.coins,
        );
        await widget.authService.updateHeldCoins(
          user['heldCoins'] as int? ?? widget.authService.heldCoins,
        );
      } catch (_) {}
      if (!mounted) return;
      setState(() => _joiningTournamentId = null);
      showInfoToast(context, "You're in the bracket!");
      _openTournament(id);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _joiningTournamentId = null);
      showErrorToast(
        context,
        e.code != null ? tournamentErrorCopy(e.code) : e.message,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _joiningTournamentId = null);
      showErrorToast(context, e.toString());
    }
  }

  Future<bool?> _confirmBuyIn(int buyIn) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        child: TrailSign(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$buyIn GOLD BUY-IN',
                style: PixelText.title(size: 18, color: AppColors.textDark),
              ),
              const SizedBox(height: 12),
              Text(
                'Your $buyIn gold is held until the bracket starts. You only '
                'get it back if the tournament is cancelled.',
                textAlign: TextAlign.center,
                style: PixelText.body(size: 13.5, color: AppColors.textMid),
              ),
              const SizedBox(height: 18),
              PillButton(
                label: 'NEVER MIND',
                variant: PillButtonVariant.primary,
                fullWidth: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                onPressed: () => Navigator.of(dialogContext).pop(false),
              ),
              const SizedBox(height: 10),
              PillButton(
                label: 'LOCK IT IN',
                variant: PillButtonVariant.accent,
                fullWidth: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                onPressed: () => Navigator.of(dialogContext).pop(true),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ArcadePageBackground(
        headerHeight: 56,
        headerColor: AppColors.roofLight,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(
                          Icons.arrow_back,
                          color: AppColors.parchmentLight,
                          size: 24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'PUBLIC RACES',
                      style: PixelText.title(
                        size: 22,
                        color: AppColors.parchmentLight,
                      ).copyWith(shadows: _textShadows),
                    ),
                  ],
                ),
              ),
              // Pinned segmented filter — shown whenever there's content to
              // filter (hidden during loading / error / the empty state).
              if (_hasAnyContent) _buildContentFilterPills(),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _load,
                  color: AppColors.accent,
                  backgroundColor: AppColors.parchment,
                  child: _buildBody(),
                ),
              ),
              const AdBannerSlot(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final state = _racesState;
    final races = state.data ?? _races;

    if (state.shouldShowInitialLoading || _loading && races.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: ListSkeleton(itemCount: 4),
      );
    }

    if (state.isError && !state.hasData) {
      return LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 48,
                  ),
                  child: LoadErrorPanel(
                    title: 'Couldn’t load public races',
                    message: 'Check your connection and try again.',
                    onRetry: _load,
                  ),
                ),
              ),
            ),
          );
        },
      );
    }

    final hasTournaments =
        _featuredTournaments.isNotEmpty || _userTournaments.isNotEmpty;

    if (races.isEmpty && !hasTournaments) {
      return LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 48,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.flag_outlined,
                        size: 48,
                        color: AppColors.textMid.withValues(alpha: 0.6),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'NO PUBLIC RACES',
                        textAlign: TextAlign.center,
                        style: PixelText.title(
                          size: 18,
                          color: AppColors.textMid,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Check back later or start your own.',
                        textAlign: TextAlign.center,
                        style: PixelText.body(
                          size: 14,
                          color: AppColors.textMid,
                        ),
                      ),
                      const SizedBox(height: 24),
                      PillButton(
                        label: 'CREATE A RACE',
                        variant: PillButtonVariant.primary,
                        fontSize: 13,
                        onPressed: _navigateToCreateRace,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    }
    // The pinned pill selects which group(s) show; ALL shows all three.
    final showFeatured =
        _filter == _PublicFilter.all || _filter == _PublicFilter.featured;
    final showTournaments =
        _filter == _PublicFilter.all || _filter == _PublicFilter.tournaments;
    final showRaces =
        _filter == _PublicFilter.all || _filter == _PublicFilter.races;

    final featuredVisible = showFeatured && _featuredTournaments.isNotEmpty;
    final userVisible = showTournaments && _userTournaments.isNotEmpty;
    final racesVisible = showRaces && races.isNotEmpty;

    final children = <Widget>[
      if (featuredVisible) ...[
        _sectionLabel('FEATURED'),
        for (final t in _featuredTournaments) _buildFeaturedTournamentCard(t),
      ],
      if (userVisible) ...[
        _sectionLabel('TOURNAMENTS'),
        for (final t in _userTournaments) _buildUserTournamentCard(t),
      ],
      if (racesVisible) ...[
        // Under ALL, only label RACES when a group sits above it; under the
        // RACES filter the header still labels the group.
        if (_filter == _PublicFilter.races || featuredVisible || userVisible)
          _sectionLabel('RACES'),
        for (final race in races) _buildRaceCard(race),
      ],
    ];

    if (children.isEmpty) {
      // The selected filter has nothing, but the screen has other content — a
      // small note keeps the pill state legible.
      children.add(_buildFilterEmpty(_emptyNoteForFilter()));
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      children: children,
    );
  }

  String _emptyNoteForFilter() {
    switch (_filter) {
      case _PublicFilter.featured:
        return 'No featured tournaments right now.';
      case _PublicFilter.tournaments:
        return 'No public tournaments right now.';
      case _PublicFilter.races:
        return 'No public races right now.';
      case _PublicFilter.all:
        return 'Nothing here yet.';
    }
  }

  Widget _buildFilterEmpty(String message) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 40, 8, 40),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: PixelText.body(size: 14, color: AppColors.textMid),
      ),
    );
  }

  /// Whether the screen currently has any listable content (drives the pinned
  /// pill's visibility). Mirrors the loading/error/empty gates in [_buildBody].
  bool get _hasAnyContent {
    final state = _racesState;
    final races = state.data ?? _races;
    if (state.shouldShowInitialLoading || (_loading && races.isEmpty)) {
      return false;
    }
    if (state.isError && !state.hasData) return false;
    return races.isNotEmpty ||
        _featuredTournaments.isNotEmpty ||
        _userTournaments.isNotEmpty;
  }

  /// The ALL / FEATURED / TOURNAMENTS / RACES segmented control — the same dark
  /// ink pill (gold-selected) built for the races tab.
  Widget _buildContentFilterPills() {
    Widget seg(String label, _PublicFilter value, Key key) {
      final selected = _filter == value;
      return Expanded(
        child: GestureDetector(
          key: key,
          onTap: () => setState(() => _filter = value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
            decoration: BoxDecoration(
              gradient: selected
                  ? const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [AppColors.pillGold, AppColors.pillGoldDark],
                    )
                  : null,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: selected ? AppColors.pillGoldShadow : Colors.transparent,
                width: 2,
              ),
              boxShadow: selected
                  ? const [
                      BoxShadow(
                        color: AppColors.pillGoldShadow,
                        offset: Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            alignment: Alignment.center,
            // FittedBox so the four labels (incl. the long "TOURNAMENTS") always
            // show in full, scaling down a touch on the narrowest phones rather
            // than truncating.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: PixelText.title(
                  size: 12,
                  color: selected ? AppColors.textDark : AppColors.parchment,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.roofDark.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.roofDark, width: 1.5),
        ),
        child: Row(
          children: [
            seg('ALL', _PublicFilter.all, const Key('public-filter-all')),
            const SizedBox(width: 4),
            seg(
              'FEATURED',
              _PublicFilter.featured,
              const Key('public-filter-featured'),
            ),
            const SizedBox(width: 4),
            seg(
              'TOURNEYS',
              _PublicFilter.tournaments,
              const Key('public-filter-tournaments'),
            ),
            const SizedBox(width: 4),
            seg('RACES', _PublicFilter.races, const Key('public-filter-races')),
          ],
        ),
      ),
    );
  }

  // Section labels sit on the parchment BODY (not the green header), so they
  // must be dark to read — the old parchment-light + shadow treatment rendered
  // as a light-on-light ghost outline. Matches the races-tab section headers.
  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4, left: 2),
      child: Text(
        text,
        style: PixelText.title(size: 14, color: AppColors.textDark),
      ),
    );
  }

  /// A featured (seeded) bracket card — always free, so no confirm dialog. JOIN
  /// flips to VIEW once I'm in; D12: JOIN is pre-disabled while I'm still alive
  /// in another same-seed bracket (with ALREADY_IN_FEATURED surfaced on tap for
  /// the race the client didn't know about).
  Widget _buildFeaturedTournamentCard(Map<String, dynamic> t) {
    final id = Tournament.id(t) ?? '';
    final joined = Tournament.amIn(t);
    final aliveElsewhere =
        !joined &&
        Tournament.aliveInSeed(_myTournaments, Tournament.seedKind(t));
    final isJoining = _joiningTournamentId == id;
    final full = Tournament.isFull(t);

    final String label;
    final PillButtonVariant variant;
    final VoidCallback? onPressed;
    if (joined) {
      label = 'VIEW';
      variant = PillButtonVariant.secondary;
      onPressed = () => _openTournament(id);
    } else if (aliveElsewhere) {
      label = 'IN A BRACKET';
      variant = PillButtonVariant.secondary;
      onPressed = null;
    } else if (full) {
      label = 'FULL';
      variant = PillButtonVariant.secondary;
      onPressed = null;
    } else {
      label = isJoining ? 'JOINING...' : 'JOIN';
      variant = PillButtonVariant.primary;
      onPressed = isJoining ? null : () => _joinTournament(t, featured: true);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TournamentGameCard(
        // No CTA glow on the full-width Public Races list cards — matches the
        // plain JOIN pill on this screen's race cards (the glow is reserved for
        // the compact featured-row cards).
        name: Tournament.name(t).toUpperCase(),
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
        onPressed: onPressed,
      ),
    );
  }

  /// A user-created public bracket card — paid joins pop the buy-in confirm.
  Widget _buildUserTournamentCard(Map<String, dynamic> t) {
    final id = Tournament.id(t) ?? '';
    final joined = Tournament.amIn(t);
    final isJoining = _joiningTournamentId == id;
    final full = Tournament.isFull(t);

    final String label;
    final PillButtonVariant variant;
    final VoidCallback? onPressed;
    if (joined) {
      label = 'VIEW';
      variant = PillButtonVariant.secondary;
      onPressed = () => _openTournament(id);
    } else if (full) {
      label = 'FULL';
      variant = PillButtonVariant.secondary;
      onPressed = null;
    } else {
      label = isJoining ? 'JOINING...' : 'JOIN';
      variant = PillButtonVariant.primary;
      onPressed = isJoining ? null : () => _joinTournament(t, featured: false);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TournamentGameCard(
        name: Tournament.name(t).toUpperCase(),
        metaLine:
            '${Tournament.sizeSubcopy(Tournament.bracketSize(t))} · '
            '${Tournament.durationSubcopy(Tournament.matchupDurationDays(t))}',
        filledLabel:
            '${Tournament.acceptedCount(t)}/${Tournament.bracketSize(t)} IN',
        // The pot (what the champion actually walks away with) is the meaningful
        // number on a paid user bracket; falls back to the crown for free ones.
        prizeLabel: 'WINNER TAKES',
        prizeValue: Tournament.championWinnings(t),
        ctaKey: Key('user-tournament-join-$id'),
        ctaLabel: label,
        ctaVariant: variant,
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildRaceCard(Map<String, dynamic> race) {
    final raceId = race['id'] as String;
    final name = race['name'] as String? ?? 'Race';
    final endsAt = DateTime.tryParse(race['endsAt'] as String? ?? '');
    final maxDurationDays = race['maxDurationDays'] as int? ?? 7;
    final participantCount = race['participantCount'] as int? ?? 0;
    // null => no participant limit (unlimited).
    final maxParticipants = race['maxParticipants'] as int?;
    final runnersLabel = maxParticipants == null
        ? '$participantCount'
        : '$participantCount/$maxParticipants';
    final buyIn = race['buyInAmount'] as int? ?? 0;
    final creator = race['creator'] as Map<String, dynamic>?;
    final creatorName = creator?['displayName'] as String? ?? 'Someone';
    final powerupsEnabled = race['powerupsEnabled'] as bool? ?? false;
    final finishReward = race['finishReward'] as Map<String, dynamic>?;
    final finishRewardPool = (finishReward?['pool'] as num?)?.toInt() ?? 0;
    final finishRewardPlaces =
        (finishReward?['paidPlaces'] as num?)?.toInt() ?? 0;
    // "TOP 3" / "WINNER" / fraction-free fallback for older backends.
    final finishRewardLabel = finishRewardPlaces == 1
        ? 'WINNER'
        : finishRewardPlaces > 1
        ? 'TOP $finishRewardPlaces'
        : 'REWARD';
    final isJoining = _joiningRaceId == raceId;

    // Races are time-based: show time remaining, not a step target.
    String timeLeftLabel;
    if (endsAt != null) {
      final remaining = endsAt.difference(DateTime.now());
      if (remaining.isNegative) {
        timeLeftLabel = 'soon';
      } else if (remaining.inDays > 0) {
        timeLeftLabel =
            '${remaining.inDays}d ${remaining.inHours.remainder(24)}h';
      } else if (remaining.inHours > 0) {
        timeLeftLabel =
            '${remaining.inHours}h ${remaining.inMinutes.remainder(60)}m';
      } else {
        timeLeftLabel = '${remaining.inMinutes}m';
      }
    } else {
      timeLeftLabel = '${maxDurationDays}d';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: RetroCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name.toUpperCase(),
              style: PixelText.title(size: 16, color: AppColors.textDark),
            ),
            const SizedBox(height: 4),
            Text(
              'BY ${atName(creatorName)}'.toUpperCase(),
              style: PixelText.body(size: 11, color: AppColors.textMid),
            ),
            // TR-206: team format + open-slot line ("2v2 · 1 slot left on
            // Blue"). Absent entirely for individual races.
            if (TeamRace.isTeamRace(race)) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    Icons.groups_rounded,
                    size: 14,
                    color: TeamRace.colorDark(RaceTeam.teamA),
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      TeamRace.publicSlotsLabel(race),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PixelText.title(
                        size: 12,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                _buildStat('ENDS IN', timeLeftLabel),
                const SizedBox(width: 16),
                _buildStat('RUNNERS', runnersLabel),
                if (buyIn > 0) ...[
                  const SizedBox(width: 16),
                  _buildStat('BUY-IN', '$buyIn'),
                ],
                if (finishRewardPool > 0) ...[
                  const SizedBox(width: 16),
                  _buildStat(finishRewardLabel, '$finishRewardPool'),
                ],
                if (powerupsEnabled) ...[
                  const SizedBox(width: 16),
                  _buildStat('POWERUPS', 'ON'),
                ],
              ],
            ),
            const SizedBox(height: 14),
            PillButton(
              label: isJoining ? 'JOINING...' : 'JOIN',
              variant: PillButtonVariant.primary,
              fontSize: 13,
              fullWidth: true,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              onPressed: isJoining ? null : () => _join(race),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: PixelText.body(size: 10, color: AppColors.textMid)),
        const SizedBox(height: 2),
        Text(
          value,
          style: PixelText.title(size: 14, color: AppColors.textDark),
        ),
      ],
    );
  }
}
