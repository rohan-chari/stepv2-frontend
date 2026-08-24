import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/material.dart';

import '../models/loadable.dart';
import '../models/race_handoff_result.dart';
import '../models/race_prize_pool.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../services/discovery_join_coordinator.dart';
import '../styles.dart';
import '../widgets/app_refresh_indicator.dart';
import '../utils/at_name.dart';
import '../utils/funded_exposure_error_copy.dart';
import '../utils/team_race.dart';
import '../utils/tournament.dart';
import '../widgets/ad_banner_slot.dart';
import '../widgets/arcade_page.dart';
import '../widgets/error_toast.dart';
import '../widgets/featured_race_card.dart';
import '../widgets/info_toast.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/pill_button.dart';
import '../widgets/retro_card.dart';
import '../widgets/tournament_game_card.dart';
import 'create_race_screen.dart';
import 'race_detail_screen.dart';
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

/// Top-level content switch for the Public Races screen: each pill narrows to a
/// single group (FEATURED is the default). Same convention as the races-tab pill.
enum _PublicFilter { featured, tournaments, races }

class _PublicRacesScreenState extends State<PublicRacesScreen> {
  static const _textShadows = [
    Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  _PublicFilter _filter = _PublicFilter.featured;

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

  // The live seeded daily/weekly races for the FEATURED strip (moved here from
  // the Races tab). Best-effort like the tournament buckets: an older backend
  // without the endpoint simply yields no strip.
  List<Map<String, dynamic>> _featuredRaces = const [];
  String? _joiningFeaturedRaceKey;
  final Set<String> _locallyElectedBucketKeys = <String>{};

  DiscoveryJoinCoordinator get _joinCoordinator => DiscoveryJoinCoordinator(
    authService: widget.authService,
    backendApiService: widget.backendApiService,
  );

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
    try {
      final browser = await widget.backendApiService.fetchPublicRaceBrowser(
        identityToken: token,
      );
      final races = _safeMapList(browser['races']);
      final resolved = browser['contract'] == 'public-race-browser-v1'
          ? browser['resolved']
          : null;
      final resolvedMap = resolved is Map ? resolved : const {};

      if (resolvedMap['featuredRaces'] == true &&
          _isMapList(browser['featuredRaces'])) {
        _featuredRaces = _safeMapList(browser['featuredRaces']);
      } else {
        unawaited(_loadFeaturedRaces(token));
      }

      final tournaments = browser['tournaments'];
      if (resolvedMap['tournaments'] == true &&
          tournaments is Map &&
          _isMapList(tournaments['featured']) &&
          _isMapList(tournaments['public'])) {
        _featuredTournaments = _safeMapList(tournaments['featured']);
        _userTournaments = _safeMapList(tournaments['public']);
      } else {
        unawaited(_loadPublicTournamentBuckets(token));
      }
      if (resolvedMap['mine'] == true &&
          tournaments is Map &&
          _isMapList(tournaments['mine'])) {
        _myTournaments = _safeMapList(tournaments['mine']);
      } else {
        unawaited(_loadMyTournamentBucket(token));
      }
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

  List<Map<String, dynamic>> _safeMapList(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final row in raw)
        if (row is Map)
          <String, dynamic>{
            for (final entry in row.entries)
              if (entry.key is String) entry.key as String: entry.value,
          },
    ];
  }

  bool _isMapList(Object? raw) =>
      raw is List && raw.every((item) => item is Map);

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
    final raceId = race['id'];
    if (raceId is! String || raceId.isEmpty) return;
    setState(() => _joiningRaceId = raceId);
    final result = await _joinCoordinator.joinRace(context, race);
    if (!mounted) return;
    setState(() => _joiningRaceId = null);
    if (result != null) {
      Navigator.of(context).pop(
        RaceHandoffResult(
          raceId: raceId,
          status: result.status,
          kind: RaceHandoffKind.joined,
        ),
      );
    }
  }

  Future<void> _loadPublicTournamentBuckets(String token) async {
    try {
      final res = await widget.backendApiService.fetchPublicTournaments(
        identityToken: token,
      );
      if (!mounted) return;
      setState(() {
        _featuredTournaments = _safeMapList(res['featured']);
        _userTournaments = _safeMapList(res['tournaments']);
      });
    } catch (_) {
      // Older backend / offline → no tournament section.
    }
  }

  Future<void> _loadMyTournamentBucket(String token) async {
    try {
      final racesRes = await widget.backendApiService.fetchRaces(
        identityToken: token,
      );
      if (!mounted) return;
      setState(() {
        _myTournaments = _safeMapList(racesRes['tournaments']);
      });
    } catch (_) {}
  }

  Future<void> _loadFeaturedRaces(String token) async {
    try {
      final featured = await widget.backendApiService.fetchFeaturedRaces(
        identityToken: token,
      );
      if (!mounted) return;
      setState(() => _featuredRaces = featured);
    } catch (_) {
      // Older backend / offline → no featured strip.
    }
  }

  /// One-tap join for a featured (seeded) race — always free, no confirm.
  Future<void> _joinFeaturedRace(Map<String, dynamic> race) async {
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) return;
    final raceId = race['raceId'];
    final bucketPrivate = race['bucketPrivate'] == true;
    final seedKind = race['seedKind'];
    final joinKey = bucketPrivate
        ? (seedKind is String && seedKind.isNotEmpty ? 'bucket:$seedKind' : '')
        : (raceId is String ? raceId : '');
    if (joinKey.isEmpty || _joiningFeaturedRaceKey != null) return;
    setState(() => _joiningFeaturedRaceKey = joinKey);
    try {
      if (bucketPrivate && raceId == null) {
        final assignment = await widget.backendApiService
            .assignSeededRaceBucket(
              identityToken: token,
              seedKind: seedKind as String,
            );
        if (assignment['elected'] == true) {
          _locallyElectedBucketKeys.add(joinKey);
        }
      } else if (raceId is String && raceId.isNotEmpty) {
        await widget.backendApiService.joinPublicRace(
          identityToken: token,
          raceId: raceId,
        );
      } else {
        return;
      }
      if (!mounted) return;
      setState(() => _joiningFeaturedRaceKey = null);
      showInfoToast(context, bucketPrivate ? "You're in!" : "You're in!");
      // Refresh so the card flips to VIEW.
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _joiningFeaturedRaceKey = null);
      showErrorToast(context, fundedExposureErrorCopy(e));
    } catch (_) {
      if (!mounted) return;
      setState(() => _joiningFeaturedRaceKey = null);
      showErrorToast(context, 'Could not join. Give it another try!');
    }
  }

  /// Opens the race screen for [raceId], refreshing on return. Used both for a
  /// featured race I'm already in (VIEW) and, since the preview-before-joining
  /// change, for a card-body tap on a public race I have not joined — the
  /// detail screen decides between participant chrome and the read-only
  /// spectator/preview banner from what the backend returns.
  void _viewFeaturedRace(String raceId) {
    if (raceId.isEmpty) return;
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => RaceDetailScreen(
              authService: widget.authService,
              raceId: raceId,
              backendApiService: widget.backendApiService,
            ),
          ),
        )
        .then((_) {
          if (mounted) _load();
        });
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
              backendApiService: widget.backendApiService,
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
    final id = Tournament.id(t) ?? '';
    if (id.isEmpty || _joiningTournamentId != null) return;
    setState(() => _joiningTournamentId = id);
    final result = await _joinCoordinator.joinTournament(
      context,
      t,
      featured: featured,
    );
    if (!mounted) return;
    setState(() => _joiningTournamentId = null);
    if (result != null) {
      showInfoToast(context, "You're in the bracket!");
      _openTournament(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ArcadePageBackground(
        headerHeight: 56,
        headerColor: AppColors.of(context).roofLight,
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
                      child: Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(
                          Icons.arrow_back,
                          color: AppColors.of(context).textLight,
                          size: 24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'PUBLIC RACES',
                      style: PixelText.title(
                        size: 22,
                        color: AppColors.of(context).textLight,
                      ).copyWith(shadows: _textShadows),
                    ),
                  ],
                ),
              ),
              // Pinned segmented filter — shown whenever there's content to
              // filter (hidden during loading / error / the empty state).
              if (_hasAnyContent) _buildContentFilterPills(),
              Expanded(
                child: AppRefreshIndicator(
                  onRefresh: _load,
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

    if (races.isEmpty && !hasTournaments && _featuredRaces.isEmpty) {
      final showFeaturedControls = _filter == _PublicFilter.featured;
      return LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                // Centered as a block within the min-height box (no Expanded —
                // this lives inside a scrollable, so flex children are illegal).
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Keep the auto-join opt-in discoverable even with no live
                  // featured races — the toggle governs FUTURE auto-joins.
                  if (showFeaturedControls) ...[
                    const SizedBox(height: 12),
                    _buildAutoJoinCard(),
                    const SizedBox(height: 32),
                  ],
                  Icon(
                    Icons.flag_outlined,
                    size: 48,
                    color: AppColors.of(context).textMid.withValues(alpha: 0.6),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'NO PUBLIC RACES',
                    textAlign: TextAlign.center,
                    style: PixelText.title(
                      size: 18,
                      color: AppColors.of(context).textMid,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Check back later or start your own.',
                    textAlign: TextAlign.center,
                    style: PixelText.body(
                      size: 14,
                      color: AppColors.of(context).textMid,
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
          );
        },
      );
    }
    // The pinned pill selects which single group shows.
    final showFeatured = _filter == _PublicFilter.featured;
    final showTournaments = _filter == _PublicFilter.tournaments;
    final showRaces = _filter == _PublicFilter.races;

    final featuredVisible =
        showFeatured &&
        (_featuredRaces.isNotEmpty || _featuredTournaments.isNotEmpty);
    final userVisible = showTournaments && _userTournaments.isNotEmpty;
    final racesVisible = showRaces && races.isNotEmpty;

    final children = <Widget>[
      // Auto-join is a featured-races setting, so surface it (visibly, not
      // buried behind the gear) whenever the featured group is in view — even
      // when no featured race is live yet, since the toggle governs FUTURE
      // auto-joins. Reuses the exact same authService-bound toggle as the sheet.
      if (showFeatured) _buildAutoJoinCard(),
      if (featuredVisible) ...[
        // FEATURED (moved here from the Races tab): the seeded daily/weekly
        // race strip first, then the seeded brackets.
        _featuredSectionHeader(),
        if (_featuredRaces.isNotEmpty) ...[
          _buildFeaturedRacesStrip(),
          const SizedBox(height: 12),
        ],
        for (final t in _featuredTournaments) _buildFeaturedTournamentCard(t),
      ],
      if (userVisible) ...[
        _sectionLabel('TOURNEYS'),
        for (final t in _userTournaments) _buildUserTournamentCard(t),
      ],
      if (racesVisible) ...[
        _sectionLabel('RACES'),
        for (final race in races) _buildRaceCard(race),
      ],
    ];

    // The auto-join card isn't "content" — base the empty note on the actual
    // race/tournament groups so a filter with nothing still shows its note.
    final hasContent = featuredVisible || userVisible || racesVisible;
    if (!hasContent) {
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
        return 'No featured races or brackets right now.';
      case _PublicFilter.tournaments:
        return 'No public tournaments right now.';
      case _PublicFilter.races:
        return 'No public races right now.';
    }
  }

  Widget _buildFilterEmpty(String message) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 40, 8, 40),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: PixelText.body(size: 14, color: AppColors.of(context).textMid),
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
        _featuredRaces.isNotEmpty ||
        _featuredTournaments.isNotEmpty ||
        _userTournaments.isNotEmpty;
  }

  bool _raceIsJoined(Map<String, dynamic> race) {
    final status = race['myStatus'];
    return status is String && status.toUpperCase() == 'ACCEPTED';
  }

  int get _featuredAvailableCount =>
      _featuredRaces.where((race) => !_raceIsJoined(race)).length +
      _featuredTournaments.where((t) => !Tournament.amIn(t)).length;

  int get _tournamentsAvailableCount =>
      _userTournaments.where((t) => !Tournament.amIn(t)).length;

  int get _racesAvailableCount =>
      (_racesState.data ?? _races).where((race) => !_raceIsJoined(race)).length;

  String _filterLabel(String label, int availableCount) =>
      '$label ($availableCount)';

  /// The FEATURED / TOURNEYS / RACES segmented control — the same dark
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
            // FittedBox so the three labels always
            // show in full, scaling down a touch on the narrowest phones rather
            // than truncating.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: PixelText.title(
                  size: 12,
                  color: selected
                      ? AppColors.of(context).textDark
                      : AppColors.of(context).textLight,
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
          color: AppColors.of(context).roofDark.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.of(context).roofDark, width: 1.5),
        ),
        child: Row(
          children: [
            seg(
              _filterLabel('FEATURED', _featuredAvailableCount),
              _PublicFilter.featured,
              const Key('public-filter-featured'),
            ),
            const SizedBox(width: 4),
            seg(
              _filterLabel('TOURNEYS', _tournamentsAvailableCount),
              _PublicFilter.tournaments,
              const Key('public-filter-tournaments'),
            ),
            const SizedBox(width: 4),
            seg(
              _filterLabel('RACES', _racesAvailableCount),
              _PublicFilter.races,
              const Key('public-filter-races'),
            ),
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
        style: PixelText.title(size: 14, color: AppColors.of(context).textDark),
      ),
    );
  }

  /// Visible, labeled auto-join card pinned above the FEATURED group. Reuses
  /// the same [_FeaturedAutoJoinToggle] the settings sheet uses, so it's bound
  /// to the identical `authService.autoJoinFeaturedRaces` /
  /// `updateFeaturedAutoJoin` state — no second source of truth. The gear sheet
  /// stays reachable from the FEATURED header for parity.
  Widget _buildAutoJoinCard() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: _FeaturedAutoJoinToggle(authService: widget.authService),
    );
  }

  /// FEATURED section header — the plain label plus the auto-join settings
  /// gear that used to sit on the races-tab strip.
  Widget _featuredSectionHeader() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4, left: 2),
      child: Row(
        children: [
          Text(
            'FEATURED',
            style: PixelText.title(
              size: 14,
              color: AppColors.of(context).textDark,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(
              Icons.settings_rounded,
              size: 20,
              color: AppColors.of(context).textMid,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: _openFeaturedSettings,
          ),
        ],
      ),
    );
  }

  // Slide-up settings sheet for the featured strip. Currently holds only the
  // auto-join toggle.
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

  /// The horizontal strip of seeded daily/weekly race cards, exactly as it
  /// rendered on the Races tab.
  Widget _buildFeaturedRacesStrip() {
    return SizedBox(
      // Keep enough vertical room for the reward, countdown, participant line,
      // and CTA at the card's readable text sizes on narrow phones.
      height: 250,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _featuredRaces.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) => _buildFeaturedRaceCard(_featuredRaces[i]),
      ),
    );
  }

  Widget _buildFeaturedRaceCard(Map<String, dynamic> race) {
    final raceId = race['raceId'];
    final safeRaceId = raceId is String && raceId.isNotEmpty ? raceId : null;
    final seedKind = race['seedKind'] as String?;
    final bucketPrivate = race['bucketPrivate'] == true;
    final rewardRaw = race['finishReward'];
    final reward = rewardRaw is Map
        ? Map<String, dynamic>.from(rewardRaw)
        : const <String, dynamic>{};
    final key = bucketPrivate
        ? (seedKind == null || seedKind.isEmpty ? '' : 'bucket:$seedKind')
        : (safeRaceId ?? '');
    final privateAssigned =
        bucketPrivate && safeRaceId != null && race['myStatus'] == 'ACCEPTED';
    final serverElected = race['myStatus'] == 'ELECTED';
    final locallyElected =
        race['myStatus'] == null &&
        key.isNotEmpty &&
        _locallyElectedBucketKeys.contains(key);
    final elected =
        bucketPrivate && !privateAssigned && (serverElected || locallyElected);
    // Only a literal null status is an unassigned virtual card. A malformed or
    // future server status must remain inert: never turn unknown private state
    // into an /assign write.
    final privateVirtual =
        bucketPrivate &&
        safeRaceId == null &&
        race['myStatus'] == null &&
        !elected;
    return FeaturedRaceCard(
      name: race['name'] as String? ?? 'Race',
      seedKind: seedKind,
      endsAt: DateTime.tryParse(race['endsAt'] as String? ?? ''),
      participantCount: privateAssigned
          ? (race['participantCount'] as num?)?.toInt() ?? 0
          : 0,
      finishRewardPool: (reward['pool'] as num?)?.toInt() ?? 0,
      finishRewardPlaces: (reward['paidPlaces'] as num?)?.toInt() ?? 0,
      isJoined: bucketPrivate
          ? privateAssigned
          : safeRaceId != null && race['myStatus'] != null,
      isFull: race['isFull'] as bool? ?? false,
      isJoining: _joiningFeaturedRaceKey == key,
      isElected: elected,
      canJoin: bucketPrivate
          ? privateVirtual && seedKind != null && seedKind.isNotEmpty
          : safeRaceId != null,
      showParticipantCount: !bucketPrivate || privateAssigned,
      onJoin: () => _joinFeaturedRace(race),
      onView: () {
        if (safeRaceId != null) _viewFeaturedRace(safeRaceId);
      },
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
        // Card body = read-only preview, so a bracket can be inspected before
        // joining. The JOIN pill above keeps joining directly; when it is
        // disabled (IN A BRACKET / FULL / JOINING...) the tap falls through
        // here and previews, which is the intended behavior.
        onCardTap: id.isEmpty ? null : () => _openTournament(id),
      ),
    );
  }

  /// A user-created public bracket card — free to join, playing for the
  /// app-funded pool.
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
        // What the champion walks away with: the app-funded pool, falling back
        // to the pot for a bracket from an older backend.
        prizeLabel: Tournament.prizePool(t) != null
            ? 'PRIZE POOL'
            : 'WINNER TAKES',
        prizeValue: Tournament.prizeCoins(t),
        ctaKey: Key('user-tournament-join-$id'),
        ctaLabel: label,
        ctaVariant: variant,
        onPressed: onPressed,
        // See _buildFeaturedTournamentCard: body previews, pill joins.
        onCardTap: id.isEmpty ? null : () => _openTournament(id),
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
    // What the field is racing for: the app-funded pool when the backend sends
    // one, else the projected pot (which is where an older backend carries it).
    final prizeCoins =
        RacePrizePool.fromRace(race)?.coins ??
        (race['projectedPotCoins'] as num?)?.toInt() ??
        0;
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
      // Tapping the card body opens the race read-only (preview before
      // joining); the JOIN pill below still joins directly. A disabled JOIN
      // ("JOINING...") registers no gesture, so its tap falls through here —
      // intended, not accidental.
      child: GestureDetector(
        key: Key('public-race-card-$raceId'),
        behavior: HitTestBehavior.opaque,
        onTap: raceId.isEmpty ? null : () => _viewFeaturedRace(raceId),
        child: RetroCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name.toUpperCase(),
                style: PixelText.title(
                  size: 16,
                  color: AppColors.of(context).textDark,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'BY ${atName(creatorName)}'.toUpperCase(),
                style: PixelText.body(
                  size: 11,
                  color: AppColors.of(context).textMid,
                ),
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
                      // P4 (item 3): icon tint on parchment.
                      color: TeamRace.textColorOn(RaceTeam.teamA, context),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        TeamRace.publicSlotsLabel(race),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PixelText.title(
                          size: 12,
                          color: AppColors.of(context).textDark,
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
                  if (prizeCoins > 0) ...[
                    const SizedBox(width: 16),
                    _buildStat('PRIZE', formatPrizeCoins(prizeCoins)),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                onPressed: isJoining ? null : () => _join(race),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: PixelText.body(size: 10, color: AppColors.of(context).textMid),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: PixelText.title(
            size: 14,
            color: AppColors.of(context).textDark,
          ),
        ),
      ],
    );
  }
}

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
                  // Auto-enrollment is conditional server-side: a user with no
                  // steps on either of the last two days is skipped (and
                  // pruned at race start), so the toggle must not promise an
                  // unconditional entry.
                  'Auto-enters you into each new challenge while you’re active.',
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
