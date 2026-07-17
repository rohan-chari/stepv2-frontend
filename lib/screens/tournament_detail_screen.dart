import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import '../utils/share_helper.dart';
import '../utils/tournament.dart';
import '../utils/tournament_bracket.dart';
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
  }) : backendApiService = backendApiService ?? BackendApiService();

  final AuthService authService;
  final String tournamentId;
  final List<Map<String, dynamic>> friends;
  final BackendApiService backendApiService;

  @override
  State<TournamentDetailScreen> createState() => _TournamentDetailScreenState();
}

class _TournamentDetailScreenState extends State<TournamentDetailScreen>
    with WidgetsBindingObserver {
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load(initial: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Reuse the race screen's pure pause/resume decision so backgrounding stops
    // the network poll + countdown, and foregrounding (after we'd been polling)
    // refreshes once then re-arms (spec §9, race_detail_screen.dart:263-296).
    switch (racePollLifecycleAction(state, wasPolling: _pollingActive)) {
      case RacePollLifecycleAction.pause:
        _pollTimer?.cancel();
        _countdownTimer?.cancel();
        break;
      case RacePollLifecycleAction.resume:
        _load();
        _startPolling();
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
    _pollTimer = Timer.periodic(const Duration(seconds: 60), (_) => _load());
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

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
          e.code != null ? tournamentErrorCopy(e.code) : e.message,
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
      await widget.authService.updateCoins(
        me['coins'] as int? ?? widget.authService.coins,
      );
      await widget.authService.updateHeldCoins(
        me['heldCoins'] as int? ?? widget.authService.heldCoins,
      );
    } catch (_) {}
  }

  Future<void> _start() async {
    await _act((token) async {
      await _api.startTournament(
        identityToken: token,
        tournamentId: widget.tournamentId,
      );
      if (mounted) showInfoToast(context, 'The bracket is set — go!');
    });
    await _load();
  }

  Future<void> _leave() async {
    await _act((token) async {
      await _api.leaveTournament(
        identityToken: token,
        tournamentId: widget.tournamentId,
      );
      await _refreshWallet(token);
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
      await _api.cancelTournament(
        identityToken: token,
        tournamentId: widget.tournamentId,
      );
      await _refreshWallet(token);
      if (mounted) Navigator.of(context).pop(true);
    });
  }

  Future<void> _join() async {
    final ok = await _confirmBuyInIfNeeded();
    if (!ok) return;
    await _act((token) async {
      await _api.joinTournament(
        identityToken: token,
        tournamentId: widget.tournamentId,
      );
      await _refreshWallet(token);
      if (mounted) showInfoToast(context, "You're in the bracket!");
    });
    await _load();
  }

  Future<void> _respond(bool accept) async {
    if (accept) {
      final ok = await _confirmBuyInIfNeeded();
      if (!ok) return;
    }
    await _act((token) async {
      await _api.respondToTournamentInvite(
        identityToken: token,
        tournamentId: widget.tournamentId,
        accept: accept,
      );
      await _refreshWallet(token);
      if (!accept && mounted) {
        Navigator.of(context).pop(true);
      }
    });
    if (accept) await _load();
  }

  Future<void> _forfeit() async {
    final t = _tournament;
    if (t == null) return;
    final ok = await _confirm(
      title: 'FORFEIT YOUR MATCHUP?',
      body: 'Your opponent advances. No refunds. You stay in the bracket as a '
          'spectator.',
      confirmLabel: 'FORFEIT',
      danger: true,
    );
    if (ok != true) return;
    await _act((token) async {
      await _api.forfeitTournament(
        identityToken: token,
        tournamentId: widget.tournamentId,
      );
    });
    await _load();
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
    await _load();
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
        'Join my "$name" bracket on Bara — last capybara standing wins! $url',
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

  /// Returns true to proceed. Shows a buy-in confirm only for a paid bracket.
  Future<bool> _confirmBuyInIfNeeded() async {
    final t = _tournament;
    final buyIn = t == null ? 0 : Tournament.buyInAmount(t);
    if (buyIn <= 0) return true;
    final ok = await _confirm(
      title: '$buyIn GOLD BUY-IN',
      body: 'Your $buyIn gold is held until the bracket starts. You only get '
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
                style: PixelText.title(size: 18, color: AppColors.textDark),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                body,
                style: PixelText.body(size: 13.5, color: AppColors.textMid),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              PillButton(
                label: danger ? 'KEEP GOING' : 'NEVER MIND',
                variant: PillButtonVariant.primary,
                fullWidth: true,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                onPressed: () => Navigator.of(dialogContext).pop(false),
              ),
              const SizedBox(height: 10),
              PillButton(
                label: confirmLabel,
                variant: PillButtonVariant.accent,
                fullWidth: true,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                onPressed: () => Navigator.of(dialogContext).pop(true),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openMatchup(String raceId) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => RaceDetailScreen(
              authService: widget.authService,
              raceId: raceId,
              friends: widget.friends,
            ),
          ),
        )
        .then((_) {
          if (mounted) _load();
        });
  }

  // -- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final t = _tournament;
    final isChampionViewer = t != null && Tournament.isChampion(t, _myUserId);

    return Scaffold(
      backgroundColor: AppColors.parchmentLight,
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
            const Positioned.fill(child: IgnorePointer(child: CelebrationConfetti())),
        ],
      ),
    );
  }

  Widget _header(Map<String, dynamic>? t) {
    final name = t == null ? 'TOURNAMENT' : Tournament.name(t).toUpperCase();
    final canShare = t != null &&
        (Tournament.isPending(t) || Tournament.isActive(t));
    final topInset = MediaQuery.of(context).padding.top;
    return Container(
      color: AppColors.roofLight,
      padding: EdgeInsets.fromLTRB(6, topInset + 6, 8, 10),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.arrow_back_rounded,
                  color: AppColors.parchment, size: 24),
            ),
          ),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PixelText.title(size: 19, color: AppColors.parchment),
            ),
          ),
          if (canShare)
            GestureDetector(
              onTap: _sharing ? null : _share,
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.ios_share_rounded,
                    color: AppColors.parchment, size: 22),
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
    final countdownEnds =
        status == TournamentStatus.active ? _currentRoundEndsAt(t) : null;

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.roofLight,
        border: Border(
          bottom: BorderSide(color: AppColors.roofEdge, width: 2),
        ),
      ),
      child: CustomPaint(
        painter: const ArcadeCheckerPainter(drawBottomStripe: false),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
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

  /// A full-height dark refresh tile matching the hero tiles (via IntrinsicHeight
  /// stretch), instead of a short square.
  Widget _refreshTile() {
    return GestureDetector(
      onTap: () => _load(),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: HomeColors.ink.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: Colors.white.withValues(alpha: 0.18), width: 2),
        ),
        child: Center(
          child: Icon(Icons.refresh_rounded,
              size: 22, color: Colors.white.withValues(alpha: 0.85)),
        ),
      ),
    );
  }

  /// Full-width "ROUND ENDS IN {time}" HUD bar (its own row under the tiles).
  Widget _countdownBar(DateTime ends) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: HomeColors.ink.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 2),
      ),
      child: Row(
        children: [
          const Icon(Icons.timer_rounded, size: 22, color: AppColors.pillGold),
          const SizedBox(width: 9),
          Text('ROUND ENDS IN',
              style: HomeText.label(
                  size: 11, color: Colors.white.withValues(alpha: 0.7))),
          const Spacer(),
          Text(_countdownShort(ends),
              style: PixelText.title(size: 20, color: Colors.white)),
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
        color: HomeColors.ink.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[
            leading,
            const SizedBox(width: 9),
          ],
          // Flexible so the tile behaves inside an Expanded slot and long values
          // (e.g. a champion's name) ellipsize instead of overflowing.
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: HomeText.label(
                        size: 10, color: Colors.white.withValues(alpha: 0.7))),
                const SizedBox(height: 3),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PixelText.title(size: 24, color: valueColor)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _prizeTile(Map<String, dynamic> t) {
    if (Tournament.hasPrize(t)) {
      return _heroTile(
        leading: const SpinningCoin(size: 28),
        label: 'CHAMPION WINS',
        value: '${Tournament.championWinnings(t)}',
        valueColor: AppColors.pillGold,
      );
    }
    // Free bracket — no coin prize; the gold value conveys the stakes (no
    // trophy/crown glyph).
    return _heroTile(
      label: 'PLAYING FOR',
      value: 'THE CROWN',
      valueColor: AppColors.pillGold,
    );
  }

  Widget _stateTile(Map<String, dynamic> t, TournamentStatus? status) {
    switch (status) {
      case TournamentStatus.active:
        return _heroTile(
          leading: const Icon(Icons.account_tree_rounded,
              size: 26, color: AppColors.pillGold),
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
          valueColor: AppColors.pillGold,
        );
      case TournamentStatus.pending:
      case TournamentStatus.cancelled:
      case null:
        return _heroTile(
          leading: const Icon(Icons.groups_2_rounded,
              size: 26, color: AppColors.pillGold),
          label: 'FILLED',
          value: '${Tournament.acceptedCount(t)}/${Tournament.bracketSize(t)}',
          valueColor: Colors.white,
        );
    }
  }

  /// Short countdown for a HUD tile (no "left" suffix — the label supplies it).
  String _countdownShort(DateTime ends) {
    final diff = ends.difference(_now);
    if (diff.isNegative) return 'soon';
    final d = diff.inDays;
    final h = diff.inHours % 24;
    final mn = diff.inMinutes % 60;
    if (d > 0) return '${d}d ${h}h';
    if (h > 0) return '${h}h ${mn}m';
    return '${mn}m';
  }

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
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.parchmentLight,
        border: Border(
          top: BorderSide(color: AppColors.parchmentBorder, width: 1.5),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: content,
        ),
      ),
    );
  }

  Widget? _activeActionButtons(Map<String, dynamic> t) {
    final liveRaceId = _myLiveRaceId(t);
    if (liveRaceId != null) {
      return Row(
        children: [
          Expanded(
            flex: 3,
            child: PillButton(
              label: 'GO TO MY MATCHUP',
              variant: PillButtonVariant.primary,
              fontSize: 13,
              fullWidth: true,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
              onPressed: () => _openMatchup(liveRaceId),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: PillButton(
              label: 'FORFEIT',
              variant: PillButtonVariant.accent,
              fontSize: 13,
              fullWidth: true,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
              onPressed: _isActing ? null : _forfeit,
            ),
          ),
        ],
      );
    }
    if (_amEliminated(t)) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.visibility_rounded,
              size: 16, color: AppColors.textMid),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              "You're out — follow the bracket to the crown.",
              style: PixelText.body(size: 13, color: AppColors.textMid),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                onPressed: _isActing ? null : () => _respond(true),
              ),
            ),
          ],
        ),
      );
    } else if (Tournament.amIn(t)) {
      buttons.add(
        Row(
          children: [
            Expanded(
              flex: 2,
              child: PillButton(
                label: _sharing ? 'SHARING…' : 'SHARE LINK',
                variant: PillButtonVariant.secondary,
                fontSize: 13,
                fullWidth: true,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                onPressed: _sharing ? null : _share,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: PillButton(
                label: 'LEAVE',
                variant: PillButtonVariant.accent,
                fontSize: 13,
                fullWidth: true,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                onPressed: _isActing ? null : _leave,
              ),
            ),
          ],
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
          const Icon(Icons.cancel_rounded, size: 40, color: AppColors.textMid),
          const SizedBox(height: 8),
          Text('TOURNAMENT CANCELLED',
              style: PixelText.title(size: 16, color: AppColors.textDark)),
          const SizedBox(height: 6),
          Text(
            Tournament.buyInAmount(t) > 0
                ? 'Every buy-in has been refunded.'
                : 'This bracket was called off.',
            textAlign: TextAlign.center,
            style: PixelText.body(size: 13.5, color: AppColors.textMid),
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
          Text(Tournament.name(t),
              style: PixelText.title(size: 20, color: AppColors.textDark)),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: chips),
          const SizedBox(height: 12),
          _plaque(
            // A coin vector only when there's a coin prize — never a trophy.
            leading: Tournament.hasPrize(t) ? const SpinningCoin(size: 16) : null,
            text: Tournament.prizePlaque(t),
            color: AppColors.pillGold,
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
          if (leading != null) ...[
            leading,
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(text,
                textAlign: TextAlign.center,
                style: PixelText.title(size: 13, color: AppColors.textDark)),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.parchmentDark,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.parchmentBorder),
      ),
      child: Text(label,
          style: PixelText.body(size: 11, color: AppColors.textMid)),
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
