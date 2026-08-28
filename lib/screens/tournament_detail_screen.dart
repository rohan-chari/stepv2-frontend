import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../services/app_route_observer.dart';
import '../services/interstitial_ad_service.dart';
import '../services/race_detail_navigation.dart';
import '../styles.dart';
import '../utils/share_helper.dart';
import '../utils/tournament.dart';
import '../utils/funded_exposure_error_copy.dart';
import '../utils/tournament_bracket.dart';
import '../widgets/ad_banner_slot.dart';
import '../widgets/celebration_confetti.dart';
import '../widgets/error_toast.dart';
import '../widgets/home_chrome.dart';
import '../widgets/info_toast.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/pill_button.dart';
import '../widgets/retro_card.dart';
import '../widgets/spinning_coin.dart';
import '../widgets/tournament_bracket_board.dart';
import '../widgets/trail_sign.dart';
import 'friend_picker_screen.dart';
import 'race_detail_screen.dart';

/// The bracket screen — one parchment/wood board per lifecycle phase:
/// PENDING lobby, ACTIVE wooden bracket, COMPLETED champion (spec §9). Each
/// matchup opens the existing [RaceDetailScreen] unchanged. Every field is read
/// through [Tournament] defensively so a differently-versioned backend never
/// crashes this build (the #1 rule).
class TournamentDetailScreen extends StatefulWidget {
  TournamentDetailScreen({
    super.key,
    required this.authService,
    required this.tournamentId,
    this.friends = const [],
    BackendApiService? backendApiService,
    this.raceDetailNavigator,
  }) : backendApiService = backendApiService ?? BackendApiService();

  final AuthService authService;
  final String tournamentId;
  final List<Map<String, dynamic>> friends;
  final BackendApiService backendApiService;
  final RaceDetailNavigator? raceDetailNavigator;

  /// Counts per-second countdown ticks so a test can prove the timer really is
  /// cancelled once a round enters settlement (spec §4). The state class is
  /// private, so this is the only seam a widget test can observe it through.
  @visibleForTesting
  static int debugCountdownTicks = 0;

  @override
  State<TournamentDetailScreen> createState() => _TournamentDetailScreenState();
}

class _TournamentDetailScreenState extends State<TournamentDetailScreen>
    with WidgetsBindingObserver, RouteAware {
  BackendApiService get _api => widget.backendApiService;
  String get _myUserId => widget.authService.userId ?? '';

  Map<String, dynamic>? _tournament;
  bool _loading = true;
  String? _error;
  bool _isActing = false;
  bool _sharing = false;

  Timer? _pollTimer;
  Timer? _countdownTimer;
  bool _pollingActive = false;
  DateTime _now = DateTime.now();

  // Guards against overlapping loads clobbering a fresher result out of order.
  int _loadSeq = 0;
  bool _routeVisible = true;
  bool _appResumed = true;
  bool _returnRefreshRunning = false;
  ModalRoute<dynamic>? _subscribedRoute;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load(initial: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null && !identical(route, _subscribedRoute)) {
      if (_subscribedRoute != null) appRouteObserver.unsubscribe(this);
      _subscribedRoute = route;
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPushNext() {
    _routeVisible = false;
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
  }

  @override
  void didPopNext() {
    _routeVisible = true;
    unawaited(_refreshAfterCoverage());
  }

  Future<void> _refreshAfterCoverage() async {
    if (!_routeVisible || !_appResumed || _returnRefreshRunning) return;
    _returnRefreshRunning = true;
    try {
      if (_pollingActive) await _load();
      if (_pollingActive) _startPolling();
      if (_tournament != null) _syncLifecycleTimers();
    } finally {
      _returnRefreshRunning = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    appRouteObserver.unsubscribe(this);
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _appResumed = false;
    } else if (state == AppLifecycleState.resumed) {
      _appResumed = true;
    }
    // Reuse the race screen's pure pause/resume decision so backgrounding stops
    // the network poll + countdown, and foregrounding (after we'd been polling)
    // refreshes once then re-arms (spec §9, race_detail_screen.dart:263-296).
    switch (racePollLifecycleAction(state, wasPolling: _pollingActive)) {
      case RacePollLifecycleAction.pause:
        _pollTimer?.cancel();
        _countdownTimer?.cancel();
        break;
      case RacePollLifecycleAction.resume:
        if (_routeVisible) unawaited(_refreshAfterCoverage());
        break;
      case RacePollLifecycleAction.none:
        break;
    }
  }

  Future<void> _load({bool initial = false}) async {
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Please sign in again.';
        });
      }
      return;
    }
    final seq = ++_loadSeq;
    if (initial && mounted) setState(() => _loading = true);
    try {
      final res = await _api.fetchTournament(
        identityToken: token,
        tournamentId: widget.tournamentId,
      );
      if (!mounted || seq != _loadSeq) return;
      final t = res['tournament'];
      setState(() {
        _tournament = t is Map<String, dynamic> ? t : <String, dynamic>{};
        _loading = false;
        _error = null;
      });
      _syncLifecycleTimers();
    } on ApiException catch (e) {
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _loading = false;
        if (_tournament == null) {
          _error = e.code != null ? tournamentErrorCopy(e.code) : e.message;
        }
      });
    } catch (_) {
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _loading = false;
        if (_tournament == null) {
          _error = 'Could not load this tournament. Pull to retry.';
        }
      });
    }
  }

  /// Poll only while the bracket is live (PENDING waiting-to-fill or ACTIVE);
  /// a COMPLETED/CANCELLED bracket is frozen, so we stop the timers entirely.
  void _syncLifecycleTimers() {
    final t = _tournament;
    final live =
        t != null && (Tournament.isPending(t) || Tournament.isActive(t));
    if (live) {
      _startPolling();
      _startCountdown();
    } else {
      _pollingActive = false;
      _pollTimer?.cancel();
      _countdownTimer?.cancel();
    }
  }

  void _startPolling() {
    _pollingActive = true;
    _pollTimer?.cancel();
    if (!_routeVisible || !_appResumed) return;
    _pollTimer = Timer.periodic(const Duration(seconds: 60), (_) => _load());
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    if (!_routeVisible || !_appResumed) return;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      TournamentDetailScreen.debugCountdownTicks++;
      setState(() => _now = DateTime.now());
      // Once the round's clock has run out the bar shows a settling state with
      // no seconds in it, so a per-second repaint buys nothing — the 60s poll
      // is what surfaces the settled result.
      final ends = _countdownEndsAt;
      if (ends != null && !_now.isBefore(ends)) {
        _countdownTimer?.cancel();
        _countdownTimer = null;
      }
    });
  }

  /// The `endsAt` the visible countdown bar is currently counting toward, so
  /// the tick above can stop itself when it passes.
  DateTime? _countdownEndsAt;

  // -- Actions -------------------------------------------------------------

  Future<T?> _act<T>(Future<T> Function(String token) fn) async {
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) return null;
    setState(() => _isActing = true);
    try {
      return await fn(token);
    } on ApiException catch (e) {
      if (mounted) {
        showErrorToast(
          context,
          isActiveCompetitionLimitError(e)
              ? fundedExposureErrorCopy(e)
              : e.code != null
              ? tournamentErrorCopy(e.code)
              : e.message,
        );
      }
      return null;
    } catch (e) {
      if (mounted) showErrorToast(context, 'Something went wrong. Try again.');
      return null;
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  Future<void> _refreshWallet(String token) async {
    try {
      final me = await _api.fetchMe(identityToken: token);
      final coins = me['coins'];
      final heldCoins = me['heldCoins'];
      await widget.authService.updateCoins(
        coins is num ? coins.toInt() : widget.authService.coins,
      );
      await widget.authService.updateHeldCoins(
        heldCoins is num ? heldCoins.toInt() : widget.authService.heldCoins,
      );
    } catch (_) {}
  }

  bool _applyReturnedTournament(Map<String, dynamic> response) {
    final raw = response['tournament'];
    if (raw is! Map ||
        raw['id'] is! String ||
        raw['id'] != widget.tournamentId ||
        raw['name'] is! String ||
        raw['status'] is! String ||
        raw['bracketSize'] is! num ||
        raw['participants'] is! List ||
        raw['rounds'] is! List) {
      return false;
    }
    final tournament = <String, dynamic>{
      for (final entry in raw.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
    setState(() {
      _tournament = tournament;
      _error = null;
      _loading = false;
    });
    _syncLifecycleTimers();
    return true;
  }

  Future<bool> _applyReturnedWallet(Map<String, dynamic> response) async {
    final wallet = response['wallet'];
    if (wallet is! Map) return false;
    final coins = wallet['coins'];
    final heldCoins = wallet['heldCoins'];
    if (coins is! num || heldCoins is! num) return false;
    await widget.authService.updateCoins(coins.toInt());
    await widget.authService.updateHeldCoins(heldCoins.toInt());
    return true;
  }

  Future<void> _consumeActionResult(
    String token,
    Map<String, dynamic> response, {
    required bool screenRemains,
    required bool walletExpected,
  }) async {
    if (screenRemains && mounted && !_applyReturnedTournament(response)) {
      await _load();
    }
    if (walletExpected && !await _applyReturnedWallet(response)) {
      await _refreshWallet(token);
    }
  }

  Future<void> _start() async {
    await _act((token) async {
      final response = await _api.startTournament(
        identityToken: token,
        tournamentId: widget.tournamentId,
      );
      await _consumeActionResult(
        token,
        response,
        screenRemains: true,
        walletExpected: false,
      );
      if (mounted) showInfoToast(context, 'The bracket is set. Go!');
    });
  }

  Future<void> _leave() async {
    final ok = await _confirm(
      title: 'LEAVE THE TOURNAMENT?',
      body:
          'Your buy-in is refunded. You can rejoin later if a spot opens '
          'up.',
      confirmLabel: 'LEAVE',
    );
    if (ok != true) return;
    await _act((token) async {
      final response = await _api.leaveTournament(
        identityToken: token,
        tournamentId: widget.tournamentId,
      );
      await _consumeActionResult(
        token,
        response,
        screenRemains: false,
        walletExpected: true,
      );
      if (mounted) Navigator.of(context).pop(true);
    });
  }

  Future<void> _cancel() async {
    final ok = await _confirm(
      title: 'CALL OFF THE TOURNAMENT?',
      body: 'Every racer gets their buy-in back. This can\'t be undone.',
      confirmLabel: 'CALL IT OFF',
    );
    if (ok != true) return;
    await _act((token) async {
      final response = await _api.cancelTournament(
        identityToken: token,
        tournamentId: widget.tournamentId,
      );
      await _consumeActionResult(
        token,
        response,
        screenRemains: false,
        walletExpected: true,
      );
      if (mounted) Navigator.of(context).pop(true);
    });
  }

  Future<void> _join() async {
    final ok = await _confirmBuyInIfNeeded();
    if (!ok) return;
    await _act((token) async {
      final response = await _api.joinTournament(
        identityToken: token,
        tournamentId: widget.tournamentId,
      );
      await _consumeActionResult(
        token,
        response,
        screenRemains: true,
        walletExpected: true,
      );
      if (mounted) showInfoToast(context, "You're in the bracket!");
    });
  }

  Future<void> _respond(bool accept) async {
    if (accept) {
      final ok = await _confirmBuyInIfNeeded();
      if (!ok) return;
    }
    await _act((token) async {
      final response = await _api.respondToTournamentInvite(
        identityToken: token,
        tournamentId: widget.tournamentId,
        accept: accept,
      );
      await _consumeActionResult(
        token,
        response,
        screenRemains: accept,
        walletExpected: true,
      );
      if (!accept && mounted) {
        Navigator.of(context).pop(true);
      }
    });
  }

  Future<void> _forfeit() async {
    final t = _tournament;
    if (t == null) return;
    final ok = await _confirm(
      title: 'FORFEIT YOUR MATCHUP?',
      body:
          'Your opponent advances. No refunds. You stay in the bracket as a '
          'spectator.',
      confirmLabel: 'FORFEIT',
      danger: true,
    );
    if (ok != true) return;
    await _act((token) async {
      final response = await _api.forfeitTournament(
        identityToken: token,
        tournamentId: widget.tournamentId,
      );
      await _consumeActionResult(
        token,
        response,
        screenRemains: true,
        walletExpected: false,
      );
    });
  }

  Future<void> _invite() async {
    final picked = await Navigator.of(context).push<(String, String)?>(
      MaterialPageRoute(
        builder: (_) => FriendPickerScreen(friends: widget.friends),
      ),
    );
    if (picked == null) return;
    await _act((token) async {
      final res = await _api.inviteToTournament(
        identityToken: token,
        tournamentId: widget.tournamentId,
        userIds: [picked.$1],
      );
      await _consumeActionResult(
        token,
        res,
        screenRemains: true,
        walletExpected: false,
      );
      final needsUpdate = (res['needsUpdate'] as List?) ?? const [];
      if (mounted) {
        if (needsUpdate.isNotEmpty) {
          showErrorToast(
            context,
            '${picked.$2} needs to update the app to join tournaments.',
          );
        } else {
          showInfoToast(context, 'Invite sent to ${picked.$2}!');
        }
      }
    });
  }

  Future<void> _share() async {
    if (_sharing) return;
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) return;
    setState(() => _sharing = true);
    try {
      final res = await _api.createTournamentShareLink(
        identityToken: token,
        tournamentId: widget.tournamentId,
      );
      final url = res['url'] as String?;
      if (url == null || url.isEmpty) {
        throw const ApiException('Could not create a share link.');
      }
      if (!mounted) return;
      final name = Tournament.name(_tournament ?? const {});
      await shareText(
        context,
        'Join my "$name" bracket on Bara. Last capybara standing wins! $url',
        subject: 'Join my bracket on Bara',
      );
    } on ApiException catch (e) {
      if (mounted) showErrorToast(context, e.message);
    } catch (e) {
      if (mounted) showErrorToast(context, 'Could not share the link.');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  /// Returns true to proceed. Funded brackets are free, so joining is one tap;
  /// the confirm survives only for a pre-flip bracket that still holds real
  /// buy-ins (charging without asking would be the worse bug).
  Future<bool> _confirmBuyInIfNeeded() async {
    final t = _tournament;
    final buyIn = t == null || Tournament.prizePool(t) != null
        ? 0
        : Tournament.buyInAmount(t);
    if (buyIn <= 0) return true;
    final ok = await _confirm(
      title: '$buyIn GOLD BUY-IN',
      body:
          'Your $buyIn gold is held until the bracket starts. You only get '
          'it back if the tournament is cancelled.',
      confirmLabel: 'LOCK IT IN',
    );
    return ok == true;
  }

  Future<bool?> _confirm({
    required String title,
    required String body,
    required String confirmLabel,
    bool danger = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        child: TrailSign(
          width: 330,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: PixelText.title(
                  size: 18,
                  color: AppColors.of(context).textDark,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                body,
                style: PixelText.body(
                  size: 13.5,
                  color: AppColors.of(context).textMid,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              PillButton(
                label: danger ? 'KEEP GOING' : 'NEVER MIND',
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
                label: confirmLabel,
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

  void _openMatchup(String raceId) {
    final navigator =
        widget.raceDetailNavigator ??
        RaceDetailNavigator.withoutInterstitials(
          authService: widget.authService,
          backendApiService: widget.backendApiService,
        );
    unawaited(
      navigator.push(
        context: context,
        raceId: raceId,
        entrySurface: RaceDetailEntrySurface.tournament,
        friends: widget.friends,
        scheduleRefresh: () => unawaited(_load()),
      ),
    );
  }

  // -- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final t = _tournament;
    final isChampionViewer = t != null && Tournament.isChampion(t, _myUserId);

    return Scaffold(
      backgroundColor: AppColors.of(context).parchmentLight,
      body: Stack(
        children: [
          Column(
            children: [
              _header(t),
              // The bracket canvas owns its own pan gesture, so there's no
              // pull-to-refresh wrapper here (it would fight the drag); the 60s
              // lifecycle poll keeps it fresh, plus a manual refresh in the strip.
              Expanded(child: _body(t)),
            ],
          ),
          // Confetti ONLY for the champion viewing their completed bracket
          // (the confetti-on-finish rule).
          if (t != null && Tournament.isCompleted(t) && isChampionViewer)
            const Positioned.fill(
              child: IgnorePointer(child: CelebrationConfetti()),
            ),
        ],
      ),
    );
  }

  /// The single destructive verb this viewer can take on this tournament right
  /// now — `'LEAVE'`, `'FORFEIT'`, or null when there is nothing to offer.
  ///
  /// The branch scoping mirrors [_pendingActionButtons]/[_activeActionButtons]
  /// exactly, because that's where these actions used to live as inline
  /// buttons. Notably the creator of a user bracket never gets `'LEAVE'`:
  /// `leaveTournament` rejects them server-side (`CREATOR_CANNOT_LEAVE`), so
  /// the option would only ever produce an error toast. They cancel instead.
  String? _tournamentLeaveAction(Map<String, dynamic>? t) {
    if (t == null) return null;
    final status = Tournament.status(t);
    if (status == TournamentStatus.pending) {
      // A featured bracket's "creator" is the system, so its participants —
      // including one who happens to match `creatorId` — take the LEAVE path,
      // same as the inline button did.
      final featured = Tournament.isFeatured(t);
      final isCreator = Tournament.creatorId(t) == _myUserId && !featured;
      if (isCreator) return null;
      if (Tournament.amInvited(t) || !Tournament.amIn(t)) return null;
      return 'LEAVE';
    }
    if (status == TournamentStatus.active) {
      return _myLiveRaceId(t) != null ? 'FORFEIT' : null;
    }
    return null;
  }

  /// Header kebab sheet, mirroring `race_detail_screen.dart`'s
  /// `_showRaceOptionsSheet`. Both entries reuse the existing [_leave] /
  /// [_forfeit] paths untouched, confirmation copy and all.
  void _showTournamentOptionsSheet(String leaveAction) {
    final isForfeit = leaveAction == 'FORFEIT';
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.of(context).parchment,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'TOURNAMENT OPTIONS',
              style: PixelText.title(
                size: 18,
                color: AppColors.of(context).textDark,
              ),
            ),
            const SizedBox(height: 16),
            PillButton(
              label: isForfeit ? 'FORFEIT MATCHUP' : 'LEAVE TOURNAMENT',
              variant: PillButtonVariant.accent,
              fontSize: 13,
              fullWidth: true,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              onPressed: _isActing
                  ? null
                  : () {
                      Navigator.of(sheetContext).pop();
                      if (isForfeit) {
                        _forfeit();
                      } else {
                        _leave();
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(Map<String, dynamic>? t) {
    final name = t == null ? 'TOURNAMENT' : Tournament.name(t).toUpperCase();
    final canShare =
        t != null && (Tournament.isPending(t) || Tournament.isActive(t));
    final leaveAction = _tournamentLeaveAction(t);
    final topInset = MediaQuery.of(context).padding.top;
    return Container(
      color: AppColors.of(context).roofLight,
      padding: EdgeInsets.fromLTRB(6, topInset + 6, 8, 10),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: EdgeInsets.all(8),
              child: Icon(
                Icons.arrow_back_rounded,
                color: AppColors.of(context).textLight,
                size: 24,
              ),
            ),
          ),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PixelText.title(
                size: 19,
                color: AppColors.of(context).textLight,
              ),
            ),
          ),
          if (canShare)
            GestureDetector(
              onTap: _sharing ? null : _share,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: EdgeInsets.all(8),
                child: Icon(
                  Icons.ios_share_rounded,
                  color: AppColors.of(context).textLight,
                  size: 22,
                ),
              ),
            ),
          if (leaveAction != null)
            GestureDetector(
              onTap: () => _showTournamentOptionsSheet(leaveAction),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  Icons.more_vert,
                  color: AppColors.of(context).textLight,
                  size: 24,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _body(Map<String, dynamic>? t) {
    if (_loading && t == null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          SkeletonBox(width: double.infinity, height: 96),
          SizedBox(height: 12),
          SkeletonBox(width: double.infinity, height: 280),
        ],
      );
    }
    if (t == null || (_error != null && t.isEmpty)) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 80),
            child: LoadErrorPanel(
              title: 'Could not load',
              message: _error ?? 'Pull to retry.',
              onRetry: () => _load(initial: true),
            ),
          ),
        ],
      );
    }

    switch (Tournament.status(t)) {
      case TournamentStatus.pending:
      case TournamentStatus.active:
      case TournamentStatus.completed:
        return _bracketLayout(t);
      case TournamentStatus.cancelled:
        return _centeredCard(_cancelledBoard(t));
      case null:
        return _centeredCard(_infoBoard(t));
    }
  }

  Widget _centeredCard(Widget child) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(14),
      children: [child],
    );
  }

  /// The marquee layout: a compact info strip, the pannable bracket canvas as
  /// the hero, and a contextual action bar — the checkered board is the star.
  Widget _bracketLayout(Map<String, dynamic> t) {
    return Column(
      children: [
        _infoStrip(t),
        // Sponsored banner (spec §3): a fixed AdBannerSlot pinned above the
        // bracket, OUTSIDE the pannable/zoomable board, so the AdMob creative
        // renders at a stable size (no "MediaView too small" warnings). Uses
        // the trackside style (SPONSOR label) + the banner ad unit, and
        // collapses to zero height on no-fill or when the kill switch is off.
        const AdBannerSlot(style: AdBannerStyle.trackside),
        Expanded(
          child: TournamentBracketBoard(
            model: buildTournamentBracket(t, _myUserId),
            onTapMyMatchup: _openMatchup,
            // Spectate any other matchup — the race screen renders read-only
            // when the viewer isn't one of its two racers.
            onTapMatchup: _openMatchup,
            stepFormatter: _fmt,
          ),
        ),
        _actionBar(t),
      ],
    );
  }

  // -- Info strip ----------------------------------------------------------

  /// The top HUD: dark ink game-tiles (prize + state, in the race-detail
  /// `_heroChip` language) over the green header band, a row of compact ink
  /// descriptor chips, and a legible status strip — so the top of the bracket
  /// screen reads with the same game-y HUD feel as the race header.
  Widget _infoStrip(Map<String, dynamic> t) {
    final status = Tournament.status(t);
    final countdownEnds = status == TournamentStatus.active
        ? _currentRoundEndsAt(t)
        : null;

    return Container(
      key: const Key('tournament-info-strip'),
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.of(context).roofLight,
        border: Border(
          bottom: BorderSide(color: AppColors.of(context).roofEdge, width: 2),
        ),
      ),
      child: CustomPaint(
        painter: const ArcadeCheckerPainter(drawBottomStripe: false),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            children: [
              // Top row: the two headline tiles + a full-height refresh tile.
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _prizeTile(t)),
                    const SizedBox(width: 8),
                    Expanded(child: _stateTile(t, status)),
                    const SizedBox(width: 8),
                    _refreshTile(),
                  ],
                ),
              ),
              // The round countdown gets its own full-width HUD bar below.
              if (countdownEnds != null) ...[
                const SizedBox(height: 8),
                _countdownBar(countdownEnds),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// HUD-tile fill. `ink` flips to cream on the night palette (it doubles as
  /// the night text color), which turned these tiles into unreadable
  /// white-on-white boards — `woodDarker` stays dark in both themes, matching
  /// the race-detail `_heroChip` fill this HUD borrows its language from.
  Color get _tileFill =>
      AppColors.of(context).woodDarker.withValues(alpha: 0.92);

  /// Gold accent for the HUD tiles. The night palette migrates `pillGold` to
  /// twilight violet, which disappears against the dark tile fill — `feedGold`
  /// stays a legible bright gold there.
  Color get _tileGold => AppColors.of(context).isDark
      ? AppColors.of(context).feedGold
      : AppColors.of(context).pillGold;

  /// A full-height dark refresh tile matching the hero tiles (via IntrinsicHeight
  /// stretch), instead of a short square.
  Widget _refreshTile() {
    void refresh() => _load();
    return Semantics(
      button: true,
      label: 'Refresh tournament',
      onTap: refresh,
      child: ExcludeSemantics(
        child: GestureDetector(
          key: const Key('tournament-refresh'),
          onTap: refresh,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: _tileFill,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.18),
                width: 2,
              ),
            ),
            child: Center(
              child: Icon(
                Icons.refresh_rounded,
                size: 22,
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Full-width "ROUND ENDS IN {time}" HUD bar (its own row under the tiles).
  ///
  /// Once `ends` passes, the whole bar swaps to a settling state: the round is
  /// genuinely over and the server catches up on the raceExpiry cron's 5-minute
  /// tick, so counting down further would be a lie (spec §4). The refresh tile
  /// beside it stays the manual way to pull the result.
  Widget _countdownBar(DateTime ends) {
    _countdownEndsAt = ends;
    final settled = _hasSettled(ends);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: _tileFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.18),
          width: 2,
        ),
      ),
      child: Row(
        children: [
          Icon(
            settled ? Icons.hourglass_bottom_rounded : Icons.timer_rounded,
            size: 22,
            color: _tileGold,
          ),
          const SizedBox(width: 9),
          Text(
            settled ? 'SETTLING' : 'ROUND ENDS IN',
            style: HomeText.label(
              size: 11,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  switchInCurve: Curves.easeOutBack,
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: ScaleTransition(scale: anim, child: child),
                  ),
                  child: settled
                      ? Text(
                          'Results in a few minutes',
                          key: const ValueKey('settling'),
                          style: PixelText.title(
                            size: 12,
                            color: Colors.white.withValues(alpha: 0.92),
                          ),
                        )
                      : Text(
                          _countdownShort(ends),
                          key: const ValueKey('ticking'),
                          style: PixelText.title(size: 20, color: Colors.white),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A dark HUD tile (the race-detail `_heroChip` treatment): ink fill, white
  /// hairline border, an optional gold accent leading widget, and a tiny
  /// uppercase label over a bold value.
  Widget _heroTile({
    Widget? leading,
    required String label,
    required String value,
    required Color valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _tileFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.18),
          width: 2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[leading, const SizedBox(width: 7)],
          // Flexible so the tile behaves inside an Expanded slot and long values
          // (e.g. a champion's name) ellipsize instead of overflowing.
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HomeText.label(
                    size: 10,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PixelText.title(size: 22, color: valueColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _prizeTile(Map<String, dynamic> t) {
    // A funded bracket's pool is paid by the app; a featured/seeded bracket
    // keeps its own minted champion prize (§4.4 branch 2).
    final pool = Tournament.prizePool(t);
    if (pool != null && pool.coins > 0 && !Tournament.isFeatured(t)) {
      return _heroTile(
        leading: const SpinningCoin(size: 24),
        label: 'PRIZE POOL',
        value: pool.formattedCoins,
        valueColor: _tileGold,
      );
    }
    if (Tournament.hasPrize(t)) {
      return _heroTile(
        leading: const SpinningCoin(size: 24),
        label: 'CHAMPION WINS',
        value: '${Tournament.championWinnings(t)}',
        valueColor: _tileGold,
      );
    }
    // Free bracket — no coin prize; the gold value conveys the stakes (no
    // trophy/crown glyph).
    return _heroTile(
      label: 'PLAYING FOR',
      value: 'THE CROWN',
      valueColor: _tileGold,
    );
  }

  Widget _stateTile(Map<String, dynamic> t, TournamentStatus? status) {
    switch (status) {
      case TournamentStatus.active:
        return _heroTile(
          leading: Icon(Icons.account_tree_rounded, size: 26, color: _tileGold),
          label: 'ROUND',
          value: '${Tournament.currentRound(t)}/${Tournament.totalRounds(t)}',
          valueColor: Colors.white,
        );
      case TournamentStatus.completed:
        final champ = Tournament.champion(t);
        // Champion conveyed by the gold value, no crown glyph.
        return _heroTile(
          label: 'CHAMPION',
          value: Tournament.isChampion(t, _myUserId)
              ? 'YOU!'
              : (champ != null ? Tournament.displayName(t, champ) : 'CROWNED'),
          valueColor: _tileGold,
        );
      case TournamentStatus.pending:
      case TournamentStatus.cancelled:
      case null:
        return _heroTile(
          leading: Icon(Icons.groups_2_rounded, size: 26, color: _tileGold),
          label: 'FILLED',
          value: '${Tournament.acceptedCount(t)}/${Tournament.bracketSize(t)}',
          valueColor: Colors.white,
        );
    }
  }

  /// Short countdown for a HUD tile (no "left" suffix — the label supplies it).
  ///
  /// Under a minute this drops to seconds — the old code floored to minutes and
  /// spent the last 59 seconds of every round reading "0m" (spec §4). Callers
  /// handle the elapsed case themselves via [_hasSettled]; this only ever
  /// formats a positive remainder.
  String _countdownShort(DateTime ends) {
    final diff = ends.difference(_now);
    if (diff.isNegative) return '0s';
    final d = diff.inDays;
    final h = diff.inHours % 24;
    final mn = diff.inMinutes % 60;
    if (d > 0) return '${d}d ${h}h';
    if (h > 0) return '${h}h ${mn}m';
    if (mn > 0) return '${mn}m';
    return '${diff.inSeconds}s';
  }

  /// True once a round's clock has run out. The server then settles on the
  /// `raceExpiry` cron's 5-minute tick, so this can be true for several minutes.
  bool _hasSettled(DateTime ends) => !_now.isBefore(ends);

  DateTime? _currentRoundEndsAt(Map<String, dynamic> t) {
    final cur = Tournament.currentRound(t);
    for (final round in Tournament.rounds(t)) {
      if ((round['round'] as num?)?.toInt() != cur) continue;
      for (final m in Tournament.matchups(round)) {
        final ends = _parseEndsAt(m);
        if (ends != null) return ends;
      }
    }
    return null;
  }

  bool _amEliminated(Map<String, dynamic> t) {
    final me = Tournament.participantById(t, _myUserId);
    return me != null && me['eliminatedInRound'] != null;
  }

  String? _myLiveRaceId(Map<String, dynamic> t) {
    final m = Tournament.myMatchup(t, _myUserId);
    if (m == null || Tournament.matchupIsCompleted(m)) return null;
    final rid = m['raceId'];
    return rid is String && rid.isNotEmpty ? rid : null;
  }

  // -- Action bar ----------------------------------------------------------

  Widget _actionBar(Map<String, dynamic> t) {
    final status = Tournament.status(t);
    Widget? content;
    if (status == TournamentStatus.pending) {
      content = _pendingActionButtons(t);
    } else if (status == TournamentStatus.active) {
      content = _activeActionButtons(t);
    }
    if (content == null) return const SizedBox.shrink();

    return Container(
      key: const Key('tournament-action-bar'),
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.of(context).parchmentLight,
        border: Border(
          top: BorderSide(
            color: AppColors.of(context).parchmentBorder,
            width: 1.5,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 9, 14, 7),
          child: content,
        ),
      ),
    );
  }

  Widget? _activeActionButtons(Map<String, dynamic> t) {
    final liveRaceId = _myLiveRaceId(t);
    if (liveRaceId != null) {
      // FORFEIT moved to the header kebab (`_showTournamentOptionsSheet`), so
      // the matchup CTA takes the whole bar.
      return PillButton(
        label: 'GO TO MY MATCHUP',
        variant: PillButtonVariant.primary,
        fontSize: 13,
        fullWidth: true,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        onPressed: () => _openMatchup(liveRaceId),
      );
    }
    if (_amEliminated(t)) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.visibility_rounded,
            size: 16,
            color: AppColors.of(context).textMid,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              "You're out. Follow the bracket to the crown.",
              style: PixelText.body(
                size: 13,
                color: AppColors.of(context).textMid,
              ),
            ),
          ),
        ],
      );
    }
    return null;
  }

  /// The PENDING lobby verbs, as a compact column of buttons for the action bar.
  Widget _pendingActionButtons(Map<String, dynamic> t) {
    final featured = Tournament.isFeatured(t);
    final isCreator = Tournament.creatorId(t) == _myUserId && !featured;
    final invited = Tournament.amInvited(t);
    final full = Tournament.isFull(t);
    final need = Tournament.openSlots(t);
    final buttons = <Widget>[];

    if (isCreator) {
      buttons.add(
        PillButton(
          label: full ? 'START TOURNAMENT' : 'NEED $need MORE',
          variant: PillButtonVariant.primary,
          fullWidth: true,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
          onPressed: (!full || _isActing) ? null : _start,
        ),
      );
      buttons.add(const SizedBox(height: 9));
      buttons.add(
        Row(
          children: [
            Expanded(
              child: PillButton(
                label: 'INVITE',
                variant: PillButtonVariant.secondary,
                fontSize: 13,
                fullWidth: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
                onPressed: _isActing ? null : _invite,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: PillButton(
                label: _sharing ? 'SHARING…' : 'SHARE LINK',
                variant: PillButtonVariant.secondary,
                fontSize: 13,
                fullWidth: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
                onPressed: _sharing ? null : _share,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: PillButton(
                label: 'CANCEL',
                variant: PillButtonVariant.accent,
                fontSize: 13,
                fullWidth: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
                onPressed: _isActing ? null : _cancel,
              ),
            ),
          ],
        ),
      );
    } else if (invited) {
      buttons.add(
        Row(
          children: [
            Expanded(
              child: PillButton(
                label: 'DECLINE',
                variant: PillButtonVariant.accent,
                fontSize: 13,
                fullWidth: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                onPressed: _isActing ? null : () => _respond(false),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: PillButton(
                label: _isActing ? 'JOINING…' : 'ACCEPT',
                variant: PillButtonVariant.primary,
                fontSize: 13,
                fullWidth: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                onPressed: _isActing ? null : () => _respond(true),
              ),
            ),
          ],
        ),
      );
    } else if (Tournament.amIn(t)) {
      // LEAVE moved to the header kebab (`_showTournamentOptionsSheet`), so
      // SHARE LINK takes the whole bar.
      buttons.add(
        PillButton(
          label: _sharing ? 'SHARING…' : 'SHARE LINK',
          variant: PillButtonVariant.secondary,
          fontSize: 13,
          fullWidth: true,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          onPressed: _sharing ? null : _share,
        ),
      );
    } else {
      buttons.add(
        PillButton(
          label: full ? 'BRACKET FULL' : (_isActing ? 'JOINING…' : 'JOIN'),
          variant: PillButtonVariant.primary,
          fullWidth: true,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
          onPressed: (full || _isActing) ? null : _join,
        ),
      );
    }

    return Column(mainAxisSize: MainAxisSize.min, children: buttons);
  }

  Widget _cancelledBoard(Map<String, dynamic> t) {
    return RetroCard(
      child: Column(
        children: [
          Icon(
            Icons.cancel_rounded,
            size: 40,
            color: AppColors.of(context).textMid,
          ),
          const SizedBox(height: 8),
          Text(
            'TOURNAMENT CANCELLED',
            style: PixelText.title(
              size: 16,
              color: AppColors.of(context).textDark,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            Tournament.buyInAmount(t) > 0
                ? 'Every buy-in has been refunded.'
                : 'This bracket was called off.',
            textAlign: TextAlign.center,
            style: PixelText.body(
              size: 13.5,
              color: AppColors.of(context).textMid,
            ),
          ),
        ],
      ),
    );
  }

  // -- Shared board bits ---------------------------------------------------

  /// The at-a-glance header: format, duration, powerups, prize plaque.
  Widget _infoBoard(Map<String, dynamic> t) {
    final size = Tournament.bracketSize(t);
    final days = Tournament.matchupDurationDays(t);
    final chips = <Widget>[
      _chip(Tournament.sizeSubcopy(size)),
      _chip(Tournament.durationSubcopy(days)),
      if (Tournament.powerupsEnabled(t)) _chip('POWERUPS ON'),
      if (Tournament.isFeatured(t)) _chip('FEATURED'),
      if (Tournament.aliveCount(t) > 0 && Tournament.isActive(t))
        _chip('${Tournament.aliveCount(t)} STILL STANDING'),
    ];
    return RetroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            Tournament.name(t),
            style: PixelText.title(
              size: 20,
              color: AppColors.of(context).textDark,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: chips),
          const SizedBox(height: 12),
          _plaque(
            // A coin vector only when there's a coin prize — never a trophy.
            leading: Tournament.hasPrize(t)
                ? const SpinningCoin(size: 16)
                : null,
            text: Tournament.prizePlaque(t),
            color: AppColors.of(context).pillGold,
          ),
        ],
      ),
    );
  }

  Widget _plaque({
    Widget? leading,
    required String text,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.55), width: 1.5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (leading != null) ...[leading, const SizedBox(width: 8)],
          Flexible(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: PixelText.title(
                size: 13,
                color: AppColors.of(context).textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.of(context).parchmentDark,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.of(context).parchmentBorder),
      ),
      child: Text(
        label,
        style: PixelText.body(size: 11, color: AppColors.of(context).textMid),
      ),
    );
  }

  // -- Helpers -------------------------------------------------------------

  DateTime? _parseEndsAt(Map<String, dynamic> m) {
    final raw = m['endsAt'];
    if (raw is String && raw.isNotEmpty) {
      return DateTime.tryParse(raw)?.toLocal();
    }
    return null;
  }

  String _fmt(int n) {
    if (n >= 1000) {
      final k = n / 1000;
      return '${k.toStringAsFixed(k >= 10 ? 0 : 1)}k';
    }
    return '$n';
  }
}
