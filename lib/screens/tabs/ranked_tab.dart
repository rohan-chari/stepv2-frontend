import 'package:flutter/material.dart';

import '../../models/loadable.dart';
import '../../services/auth_service.dart';
import '../../services/backend_api_service.dart';
import '../../styles.dart';
import '../../utils/at_name.dart';
import '../../widgets/app_avatar.dart';
import '../../widgets/home_course_track.dart'
    show AnimatedCapybaraWithAccessories;
import '../../widgets/friend_request_sheet.dart';
import '../../widgets/game_container.dart';
import '../../widgets/loading_skeleton.dart';
import '../../widgets/tier_badge.dart';

/// Ranked, weekly-cohort edition. Self-fetching like [LeaderboardTab];
/// `refreshNonce` is bumped by the shell when the tab is revealed so it
/// re-syncs. Tries `/ranked/v2` (weekly cohorts) first and falls back to the
/// legacy `/ranked` season ladder when the backend predates v2, so this build
/// works against both backend generations. Degrades safely: a backend with
/// neither endpoint renders a calm "coming soon" state rather than an error,
/// and a user with no cohort yet sees an explicit join hint — never a fake
/// number. All v2 thresholds/zones/rewards come from the server; nothing is
/// hardcoded here (the legacy RP checkpoint table below taught us why).
class RankedTab extends StatefulWidget {
  final AuthService authService;
  final BackendApiService? backendApiService;
  final int refreshNonce;

  const RankedTab({
    super.key,
    required this.authService,
    this.backendApiService,
    this.refreshNonce = 0,
  });

  @override
  State<RankedTab> createState() => _RankedTabState();
}

class _RankedTabState extends State<RankedTab> {
  late final BackendApiService _api;

  Loadable<List<Map<String, dynamic>>> _state = const Loadable.initial();

  // Legacy (/ranked) season-ladder state, used when the backend predates v2.
  List<Map<String, dynamic>> _ladder = [];
  Map<String, dynamic>? _currentUser;
  Map<String, dynamic>? _season;
  Map<RankedTier, int> _rewardByTier = {};

  // Weekly-cohort (/ranked/v2) state.
  bool _v2 = false;
  Map<String, dynamic>? _week;
  Map<String, dynamic>? _v2Me;
  Map<String, dynamic>? _cohort;
  Map<String, dynamic>? _lastWeek;
  List<Map<String, dynamic>> _v2Tiers = [];

  // True when the backend has no Ranked endpoint yet (old prod serving a newer
  // app). Treated as "coming soon", not an error.
  bool _unavailable = false;

  // v2 progressive-disclosure UI state.
  bool _groupExpanded = false; // "See full group" vs the focused window

  // Matches the title treatment on the Races/Leaderboard headers.
  static const _headerShadows = [
    Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  @override
  void initState() {
    super.initState();
    _api = widget.backendApiService ?? BackendApiService();
    _load();
  }

  @override
  void didUpdateWidget(covariant RankedTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshNonce != oldWidget.refreshNonce) _load();
  }

  Future<void> _load() async {
    final previous = _ladder;
    if (mounted) {
      setState(() {
        _state = previous.isEmpty
            ? const Loadable.loading()
            : Loadable.refreshing(previous);
      });
    }

    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) {
      if (mounted) {
        setState(
          () => _state = Loadable.error(
            'Not signed in.',
            data: previous.isEmpty ? null : previous,
          ),
        );
      }
      return;
    }

    try {
      final data = await _api.fetchRankedV2(identityToken: token);
      if (!mounted) return;
      setState(() {
        _unavailable = false;
        _v2 = true;
        _week = data['week'] as Map<String, dynamic>?;
        _v2Me = data['currentUser'] as Map<String, dynamic>?;
        _cohort = data['cohort'] as Map<String, dynamic>?;
        _lastWeek = data['lastWeek'] as Map<String, dynamic>?;
        _v2Tiers = (data['tiers'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .toList();
        _state = const Loadable.success([]);
      });
    } on ApiException {
      if (!mounted) return;
      // 404 → backend predates weekly cohorts. Any other API failure → the
      // legacy ladder may still be serving; degrading to it beats an error
      // panel. _loadLegacy owns the error state if both endpoints fail.
      await _loadLegacy(token, previous);
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _state = Loadable.error(
          e.toString(),
          data: previous.isEmpty ? null : previous,
        ),
      );
    }
  }

  Future<void> _loadLegacy(
    String token,
    List<Map<String, dynamic>> previous,
  ) async {
    try {
      final data = await _api.fetchRanked(identityToken: token);
      if (!mounted) return;
      setState(() {
        _unavailable = false;
        _v2 = false;
        _season = data['season'] as Map<String, dynamic>?;
        _currentUser = data['currentUser'] as Map<String, dynamic>?;
        _ladder = (data['ladder'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .toList();
        _rewardByTier = {
          for (final t
              in (data['tiers'] as List? ?? [])
                  .whereType<Map<String, dynamic>>())
            rankedTierFromKey(t['key'] as String?):
                (t['reward'] as num?)?.toInt() ?? 0,
        };
        _state = Loadable.success(_ladder);
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      // 404 on both endpoints → this build is newer than the deployed backend.
      // Don't alarm the user; Ranked simply isn't live for them yet.
      if (e.statusCode == 404) {
        setState(() {
          _unavailable = true;
          _state = const Loadable.success([]);
        });
        return;
      }
      setState(
        () => _state = Loadable.error(
          e.toString(),
          data: previous.isEmpty ? null : previous,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _state = Loadable.error(
          e.toString(),
          data: previous.isEmpty ? null : previous,
        ),
      );
    }
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
            onRefresh: _load,
            color: AppColors.accent,
            backgroundColor: AppColors.parchment,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [SliverToBoxAdapter(child: _buildShell())],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildShell() {
    return Column(
      children: [
        _buildHeader(),
        ColoredBox(
          color: AppColors.parchment,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
            child: _buildBody(),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.roofLight,
        border: Border(bottom: BorderSide(color: AppColors.roofDark, width: 1)),
      ),
      child: CustomPaint(
        painter: const ArcadeCheckerPainter(drawBottomStripe: false),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'RANKED',
                      style: PixelText.title(
                        size: 28,
                        color: AppColors.parchment,
                      ).copyWith(shadows: _headerShadows),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _seasonLabel(),
                      style: PixelText.body(
                        size: 12,
                        color: AppColors.parchment.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
              _SeasonCountdown(title: _seasonSubtitle()),
            ],
          ),
        ),
      ),
    );
  }

  String _seasonLabel() {
    if (_v2) {
      final index = (_week?['index'] as num?)?.toInt();
      return index == null
          ? 'Beat your cohort by walking'
          : 'Week $index · beat your cohort by walking';
    }
    final index = (_season?['index'] as num?)?.toInt();
    return index == null
        ? 'Walk to earn Ranked Points'
        : 'Season $index · climb the ladder by walking';
  }

  int? _seasonDaysLeft() {
    final source = _v2 ? (_week?['endsOn']) : (_season?['endsAt']);
    final ends = DateTime.tryParse(source?.toString() ?? '');
    if (ends == null) return null;
    final now = DateTime.now();
    if (ends.isBefore(now)) return 0;
    final hours = ends.difference(now).inHours;
    return (hours / 24).ceil();
  }

  String _seasonSubtitle() {
    final days = _seasonDaysLeft();
    if (days == null) {
      return _v2 ? 'Resets every Monday' : 'Walk to earn Ranked Points';
    }
    if (days > 1) return '$days days left';
    if (days == 1) return '1 day left';
    return 'ends today';
  }

  // RP checkpoints (floor → the band you enter at that floor), ascending across
  // divisions AND tiers. Mirrors the backend ladder in steptracker-api's
  // src/constants/rankedTiers.js — keep the two in sync. Drives the
  // division-aware "X RP to <next>" hint and the progress bars.
  static const List<(int, String)> _rankCheckpoints = [
    (0, 'Bronze III'),
    (67, 'Bronze II'),
    (133, 'Bronze I'),
    (200, 'Silver III'),
    (317, 'Silver II'),
    (433, 'Silver I'),
    (550, 'Gold III'),
    (833, 'Gold II'),
    (1116, 'Gold I'),
    (1400, 'Diamond'),
  ];

  // RP to the NEXT division/tier checkpoint — not skipping straight to the next
  // tier — so a Bronze II player sees "… to Bronze I", not "… to Silver I".
  String _rankStatus(RankedTier tier, int points) {
    for (final (floor, name) in _rankCheckpoints) {
      if (points < floor) return '${floor - points} RP to $name';
    }
    return 'Top tier';
  }

  // Progress within the user's current division band (floor → next checkpoint).
  double _tierProgress(RankedTier tier, int points) {
    var lo = 0;
    int? hi;
    for (final (floor, _) in _rankCheckpoints) {
      if (points >= floor) {
        lo = floor;
      } else {
        hi = floor;
        break;
      }
    }
    if (hi == null) return 1;
    return ((points - lo) / (hi - lo)).clamp(0.05, 1).toDouble();
  }

  Widget _buildBody() {
    final state = _state;

    if (state.shouldShowInitialLoading) {
      return Column(
        children: const [
          _HeroSkeleton(),
          SizedBox(height: 14),
          ListSkeleton(itemCount: 6, showAvatar: true),
        ],
      );
    }

    if (state.isError && !state.hasData) {
      return LoadErrorPanel(
        title: 'Couldn’t load Ranked',
        message: 'Check your connection and try again.',
        onRetry: _load,
      );
    }

    if (_unavailable) return const _ComingSoonPanel();

    return Column(
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
        if (_v2)
          ..._buildV2Body()
        else ...[
          _buildHero(),
          if (_ladder.isNotEmpty) ...[
            const SizedBox(height: 14),
            _buildLadder(),
          ],
        ],
      ],
    );
  }

  // ── Weekly-cohort (v2) UI ──────────────────────────────────────────────────

  static String _fmtSteps(int n) => n.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );

  String _tierLabelForKey(String? key) {
    for (final t in _v2Tiers) {
      if (t['key'] == key) return t['label'] as String? ?? key ?? '';
    }
    return rankedTierFromKey(key).label;
  }

  // The tier above/below the given key on the server-provided ladder.
  String? _adjacentTierKey(String? key, int delta) {
    final index = _v2Tiers.indexWhere((t) => t['key'] == key);
    if (index == -1) return null;
    final next = index + delta;
    if (next < 0 || next >= _v2Tiers.length) return null;
    return _v2Tiers[next]['key'] as String?;
  }

  List<Widget> _buildV2Body() {
    final me = _v2Me;
    final inCohort = me != null && me['ranked'] == true && _cohort != null;
    final last = _buildLastWeekBanner();

    return [
      if (last != null) ...[last, const SizedBox(height: 14)],
      if (!inCohort)
        _buildJoinCard()
      else ...[
        _buildStatusHero(),
        const SizedBox(height: 16),
        _buildGroupSection(),
      ],
    ];
  }

  // 1st, 2nd, 3rd, 4th … for plain-language rank phrasing.
  static String _ordinal(int n) {
    if (n <= 0) return '$n';
    final m = n % 100;
    final suffix = (m >= 11 && m <= 13)
        ? 'th'
        : switch (n % 10) {
            1 => 'st',
            2 => 'nd',
            3 => 'rd',
            _ => 'th',
          };
    return '$n$suffix';
  }

  // Collapses the cohort + the user's standing into one plain-language status:
  // where they sit, and the single most motivating number (how many steps to
  // move up, stay clear of the drop, or the lead they're defending). Computed
  // client-side from the members list the server already returns.
  _V2Status _status() {
    final me = _v2Me!;
    final cohort = _cohort!;
    final rank = (me['rank'] as num?)?.toInt() ?? 0;
    final mySteps = (me['weeklySteps'] as num?)?.toInt() ?? 0;
    final size = (cohort['size'] as num?)?.toInt() ?? 0;
    final promote = (cohort['promoteCount'] as num?)?.toInt() ?? 0;
    final demote = (cohort['demoteCount'] as num?)?.toInt() ?? 0;
    final projected = (me['projectedCoins'] as num?)?.toInt() ?? 0;
    final tier = rankedTierFromKey(me['tier'] as String?);
    final zone = me['zone'] as String?;

    final upKey = _adjacentTierKey(me['tier'] as String?, 1);
    final downKey = _adjacentTierKey(me['tier'] as String?, -1);
    final upTier = upKey == null ? null : _tierLabelForKey(upKey);
    final downTier = downKey == null ? null : _tierLabelForKey(downKey);
    var promoCoins = 0;
    for (final t in _v2Tiers) {
      if (t['key'] == upKey) {
        promoCoins = (t['promotionBonus'] as num?)?.toInt() ?? 0;
      }
    }

    final stepsByRank = <int, int>{};
    for (final m
        in (cohort['members'] as List? ?? [])
            .whereType<Map<String, dynamic>>()) {
      final r = (m['rank'] as num?)?.toInt();
      if (r != null) stepsByRank[r] = (m['weeklySteps'] as num?)?.toInt() ?? 0;
    }

    final inPromo = zone == 'PROMOTION';
    final inDemo = zone == 'DEMOTION';

    int? gapUp; // steps to overtake the lowest currently-promoted walker
    if (!inPromo && promote > 0 && promote < size) {
      final target = stepsByRank[promote];
      if (target != null) gapUp = (target - mySteps + 1).clamp(1, 1 << 30);
    }
    int?
    leadOverCut; // when promoting: lead over the first walker below the line
    if (inPromo && promote < size) {
      final below = stepsByRank[promote + 1];
      if (below != null) leadOverCut = (mySteps - below).clamp(0, 1 << 30);
    }
    int?
    gapSafe; // when in the drop zone: steps to reach the lowest safe walker
    if (inDemo && demote > 0) {
      final target = stepsByRank[size - demote];
      if (target != null) gapSafe = (target - mySteps + 1).clamp(1, 1 << 30);
    }

    final kind = rank == 1
        ? 'top'
        : inPromo
        ? 'promo'
        : inDemo
        ? 'danger'
        : 'safe';

    return _V2Status(
      rank: rank,
      size: size,
      promote: promote,
      demote: demote,
      kind: kind,
      gapUp: gapUp,
      gapSafe: gapSafe,
      leadOverCut: leadOverCut,
      upTier: upTier,
      downTier: downTier,
      promoCoins: promoCoins,
      projectedCoins: projected,
      tier: tier,
    );
  }

  // The hero: one glanceable answer to "how am I doing?" — status-tinted, with
  // a single big actionable number, a plain caption, and a position bar.
  Widget _buildStatusHero() {
    final s = _status();
    final tier = s.tier;

    final Color bg, fg, numColor, pillBg, pillFg, border;
    final String headline;
    switch (s.kind) {
      case 'top':
      case 'promo':
        bg = AppColors.roofLight;
        fg = AppColors.parchment;
        numColor = Colors.white;
        pillBg = AppColors.pillGold;
        pillFg = AppColors.textDark;
        border = AppColors.roofDark;
        headline = s.kind == 'top' ? 'LEADING' : 'MOVING UP';
      case 'danger':
        bg = AppColors.pillTerra;
        fg = AppColors.parchment;
        numColor = Colors.white;
        pillBg = AppColors.parchment;
        pillFg = AppColors.pillTerraShadow;
        border = AppColors.pillTerraShadow;
        headline = 'AT RISK';
      default:
        bg = AppColors.parchmentLight;
        fg = AppColors.textDark;
        numColor = AppColors.accent;
        pillBg = AppColors.parchmentDark;
        pillFg = AppColors.textDark;
        border = AppColors.parchmentBorder;
        headline = 'HOLDING';
    }

    final String big, caption;
    switch (s.kind) {
      case 'top':
        big = _ordinal(s.rank);
        caption = s.size > 1
            ? 'You lead all ${s.size} walkers this week'
            : 'Top of your group';
      case 'promo':
        if (s.leadOverCut != null) {
          big = _fmtSteps(s.leadOverCut!);
          caption = 'steps ahead of the move-up line — hold it';
        } else {
          big = _ordinal(s.rank);
          caption = s.upTier != null
              ? 'on track to reach ${s.upTier}'
              : 'in the move-up zone';
        }
      case 'danger':
        if (s.gapSafe != null) {
          big = _fmtSteps(s.gapSafe!);
          caption = 'more steps to climb out of the drop zone';
        } else {
          big = _ordinal(s.rank);
          caption = 'in the drop zone — keep walking';
        }
      default:
        if (s.gapUp != null && s.upTier != null) {
          big = _fmtSteps(s.gapUp!);
          caption =
              'more steps to pass ${_ordinal(s.promote)} and reach ${s.upTier}';
        } else {
          big = _ordinal(s.rank);
          caption = 'holding ${tier.label}';
        }
    }

    final daysLeft = _seasonDaysLeft();
    final weekIndex = (_week?['index'] as num?)?.toInt();
    final metaParts = <String>[
      if (weekIndex != null) 'Week $weekIndex',
      if (daysLeft != null)
        daysLeft > 1
            ? '$daysLeft days left'
            : daysLeft == 1
            ? '1 day left'
            : 'ends today',
    ];

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border.withValues(alpha: 0.5), width: 1.5),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        children: [
          Row(
            children: [
              TierMedal(tier: tier, size: 42),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tier.label.toUpperCase(),
                      style: PixelText.title(size: 18, color: fg),
                    ),
                    if (metaParts.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        metaParts.join(' · '),
                        style: PixelText.body(
                          size: 11,
                          color: fg.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              _StatusPill(label: headline, bg: pillBg, fg: pillFg),
            ],
          ),
          const SizedBox(height: 14),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              big,
              style: PixelText.number(size: 46, color: numColor),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            caption,
            textAlign: TextAlign.center,
            style: PixelText.body(size: 13, color: fg),
          ),
          const SizedBox(height: 14),
          _PositionBar(
            rank: s.rank,
            size: s.size,
            promote: s.promote,
            demote: s.demote,
          ),
          const SizedBox(height: 10),
          _heroFooter(s, fg),
          const SizedBox(height: 12),
          _howItWorksButton(fg),
        ],
      ),
    );
  }

  // A "How Ranked works" button that lives inside the main card and opens the
  // explainer as a bottom sheet — discoverable without cluttering the screen.
  Widget _howItWorksButton(Color fg) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: _showHowItWorks,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.help_outline_rounded, size: 15, color: fg),
              const SizedBox(width: 6),
              Text(
                'How Ranked works',
                style: PixelText.body(size: 12, color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heroFooter(_V2Status s, Color fg) {
    final parts = <String>[
      '${_ordinal(s.rank)} of ${s.size}',
      if (s.promote > 0) 'top ${s.promote} move up',
      if (s.demote > 0) 'bottom ${s.demote} drop',
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            parts.join('  ·  '),
            textAlign: TextAlign.center,
            style: PixelText.body(size: 11, color: fg.withValues(alpha: 0.85)),
          ),
        ),
        if (s.projectedCoins > 0) ...[
          const SizedBox(width: 8),
          const Icon(Icons.paid_rounded, size: 13, color: AppColors.medalGold),
          const SizedBox(width: 3),
          Text(
            '+${s.projectedCoins}',
            style: PixelText.title(size: 12, color: fg),
          ),
        ],
      ],
    );
  }

  // "Promoted to Gold! +200 coins" — shown for the week right after a settled
  // result so Monday opens with the payoff, not a blank slate.
  Widget? _buildLastWeekBanner() {
    final last = _lastWeek;
    if (last == null) return null;
    final currentIndex = (_week?['index'] as num?)?.toInt();
    final lastIndex = (last['weekIndex'] as num?)?.toInt();
    // Only the freshest result; older settled weeks aren't news anymore.
    if (currentIndex != null &&
        lastIndex != null &&
        lastIndex < currentIndex - 1) {
      return null;
    }

    final outcome = last['outcome'] as String?;
    final coins =
        ((last['rewardCoins'] as num?)?.toInt() ?? 0) +
        ((last['promotionCoins'] as num?)?.toInt() ?? 0);
    final resultTier = rankedTierFromKey(last['resultTier'] as String?);

    final (label, color) = switch (outcome) {
      'PROMOTE' => ('Promoted to ${resultTier.label}!', resultTier.color),
      'DEMOTE' => ('Moved down to ${resultTier.label}', AppColors.textMid),
      'HOLD' when coins > 0 => ('Held ${resultTier.label}', resultTier.color),
      _ => (null, AppColors.textMid),
    };
    if (label == null) return null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.6), width: 1.2),
      ),
      child: Row(
        children: [
          TierMedal(tier: resultTier, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LAST WEEK',
                  style: PixelText.body(size: 9, color: AppColors.textMid),
                ),
                Text(
                  label,
                  style: PixelText.title(size: 14, color: AppColors.textDark),
                ),
              ],
            ),
          ),
          if (coins > 0) ...[
            const Icon(
              Icons.paid_rounded,
              size: 15,
              color: AppColors.medalGold,
            ),
            const SizedBox(width: 3),
            Text(
              '+$coins',
              style: PixelText.title(size: 15, color: AppColors.textDark),
            ),
          ],
        ],
      ),
    );
  }

  // Active week, but the user hasn't synced steps yet — they get a group on
  // their next sync, not next Monday.
  Widget _buildJoinCard() {
    final tier = rankedTierFromKey(_v2Me?['tier'] as String?);
    final shown = tier == RankedTier.unranked ? RankedTier.bronze : tier;
    final weekIndex = (_week?['index'] as num?)?.toInt();
    return Container(
      decoration: BoxDecoration(
        color: AppColors.parchmentLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.parchmentBorder, width: 1.5),
      ),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Column(
        children: [
          TierMedal(tier: shown, size: 96),
          const SizedBox(height: 12),
          Text(
            "You're in${weekIndex != null ? ' — Week $weekIndex' : ''}",
            style: PixelText.title(size: 18, color: AppColors.textDark),
          ),
          const SizedBox(height: 6),
          Text(
            'Walk 5,000+ steps today to join this week’s ${shown.label} '
            'group — about 30 walkers at your level — and start climbing.',
            textAlign: TextAlign.center,
            style: PixelText.body(size: 13, color: AppColors.textMid),
          ),
          const SizedBox(height: 10),
          _howItWorksButton(AppColors.accent),
        ],
      ),
    );
  }

  // "Your group" — progressive disclosure. Always shows the top six plus the
  // walkers right around you (with a "…" gap between), and a "See full group"
  // toggle to reveal everyone. Leading with the whole 30-row list is what made
  // this feel like homework.
  Widget _buildGroupSection() {
    final cohort = _cohort!;
    final size = (cohort['size'] as num?)?.toInt() ?? 0;
    final promote = (cohort['promoteCount'] as num?)?.toInt() ?? 0;
    final demote = (cohort['demoteCount'] as num?)?.toInt() ?? 0;
    final myRank = (_v2Me?['rank'] as num?)?.toInt() ?? 0;
    final tier = rankedTierFromKey(cohort['tier'] as String?);

    final memberByRank = <int, Map<String, dynamic>>{};
    for (final m
        in (cohort['members'] as List? ?? [])
            .whereType<Map<String, dynamic>>()) {
      final r = (m['rank'] as num?)?.toInt();
      if (r != null) memberByRank[r] = m;
    }
    final rewardByRank = <int, int>{
      for (final r
          in (cohort['rewards'] as List? ?? [])
              .whereType<Map<String, dynamic>>())
        (r['rank'] as num?)?.toInt() ?? 0: (r['coins'] as num?)?.toInt() ?? 0,
    };

    // Which ranks to show when collapsed: the top six, plus the walkers right
    // around the user (a "…" gap is drawn between when they're far apart).
    List<int> visibleRanks;
    if (_groupExpanded) {
      visibleRanks = [for (var r = 1; r <= size; r++) r];
    } else {
      final want = <int>{for (var r = 1; r <= 6 && r <= size; r++) r};
      want.addAll([myRank - 1, myRank, myRank + 1]);
      visibleRanks = want.where((r) => r >= 1 && r <= size).toList()..sort();
    }

    final children = <Widget>[
      Row(
        children: [
          const Icon(Icons.groups_rounded, size: 16, color: AppColors.textDark),
          const SizedBox(width: 8),
          Text(
            'Your group',
            style: PixelText.title(size: 15, color: AppColors.textDark),
          ),
          const Spacer(),
          Text(
            '$size walkers',
            style: PixelText.body(size: 11, color: AppColors.textMid),
          ),
        ],
      ),
      const SizedBox(height: 2),
      Text(
        [
          if (promote > 0) 'Top $promote move up',
          if (demote > 0) 'bottom $demote drop',
        ].join(' · '),
        style: PixelText.body(size: 11, color: AppColors.textMid),
      ),
      const SizedBox(height: 8),
      ..._groupRows(
        visibleRanks,
        memberByRank,
        rewardByRank,
        tier,
        size,
        promote,
        demote,
      ),
      const SizedBox(height: 4),
      Center(
        child: TextButton(
          onPressed: () => setState(() => _groupExpanded = !_groupExpanded),
          style: TextButton.styleFrom(
            minimumSize: Size.zero,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            _groupExpanded ? 'Show less' : 'See full group ($size)',
            style: PixelText.body(size: 12, color: AppColors.accent),
          ),
        ),
      ),
    ];

    return Column(children: children);
  }

  // Renders the given ranks as rows, inserting the move-up / drop line markers
  // at the right boundaries and a "…" gap where ranks aren't contiguous.
  List<Widget> _groupRows(
    List<int> ranks,
    Map<int, Map<String, dynamic>> memberByRank,
    Map<int, int> rewardByRank,
    RankedTier tier,
    int size,
    int promote,
    int demote,
  ) {
    final moveUpBefore = (promote > 0 && promote < size) ? promote + 1 : -1;
    final dropBefore = (demote > 0) ? size - demote + 1 : -1;
    final up = _tierLabelForKey(
      _adjacentTierKey(_cohort?['tier'] as String?, 1),
    );
    final down = _tierLabelForKey(
      _adjacentTierKey(_cohort?['tier'] as String?, -1),
    );

    final out = <Widget>[];
    int? prev;
    for (final r in ranks) {
      if (prev != null && r - prev > 1) {
        out.add(const _GapRow());
      }
      if (r == moveUpBefore) {
        out.add(
          _LineMarker(
            label: 'Top $promote move up to $up',
            color: const Color(0xFF3E8E4B),
            icon: Icons.arrow_upward_rounded,
          ),
        );
      }
      if (r == dropBefore) {
        out.add(
          _LineMarker(
            label: 'Bottom $demote drop to $down',
            color: const Color(0xFFB4503C),
            icon: Icons.arrow_downward_rounded,
          ),
        );
      }
      final m = memberByRank[r];
      if (m != null) {
        out.add(_buildCohortRow(m, tier: tier, reward: rewardByRank[r] ?? 0));
      }
      prev = r;
    }
    return out;
  }

  Widget _buildCohortRow(
    Map<String, dynamic> m, {
    required RankedTier tier,
    required int reward,
  }) {
    final rank = (m['rank'] as num?)?.toInt();
    final userId = m['userId'] as String?;
    final isMe = _isMe(userId);
    final displayName = m['displayName'] as String? ?? 'Anonymous';
    final profilePhotoUrl = m['profilePhotoUrl'] as String?;
    final weeklySteps = (m['weeklySteps'] as num?)?.toInt() ?? 0;
    final zone = m['zone'] as String?;
    final zoneColor = switch (zone) {
      'PROMOTION' => const Color(0xFF3E8E4B),
      'DEMOTION' => const Color(0xFFB4503C),
      _ => Colors.transparent,
    };

    final content = Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
      decoration: BoxDecoration(
        color: isMe
            ? AppColors.accent.withValues(alpha: 0.14)
            : AppColors.parchment,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isMe
              ? AppColors.accent.withValues(alpha: 0.45)
              : AppColors.parchmentBorder.withValues(alpha: 0.6),
          width: isMe ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(width: 3, height: 30, color: zoneColor),
          const SizedBox(width: 6),
          SizedBox(
            width: 24,
            child: Text(
              rank != null ? '$rank' : '--',
              textAlign: TextAlign.center,
              style: PixelText.body(size: 12, color: AppColors.textMid),
            ),
          ),
          const SizedBox(width: 8),
          AppAvatar(
            name: displayName,
            imageUrl: profilePhotoUrl,
            size: 34,
            isUser: isMe,
            borderColor: isMe ? AppColors.accent : tier.color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              atName(displayName),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PixelText.body(
                size: 13,
                color: isMe ? AppColors.accent : AppColors.textDark,
              ),
            ),
          ),
          if (reward > 0) ...[
            const Icon(
              Icons.paid_rounded,
              size: 12,
              color: AppColors.medalGold,
            ),
            const SizedBox(width: 2),
            Text(
              '$reward',
              style: PixelText.body(size: 10, color: AppColors.textMid),
            ),
            const SizedBox(width: 8),
          ],
          SizedBox(
            width: 62,
            child: Text(
              _fmtSteps(weeklySteps),
              textAlign: TextAlign.right,
              style: PixelText.title(
                size: 12,
                color: isMe ? AppColors.accent : AppColors.textDark,
              ),
            ),
          ),
        ],
      ),
    );

    if (isMe || userId == null || userId.isEmpty) return content;

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () => showFriendRequestSheet(
          context: context,
          authService: widget.authService,
          backendApiService: _api,
          userId: userId,
          displayName: displayName,
          profilePhotoUrl: profilePhotoUrl,
        ),
        child: content,
      ),
    );
  }

  // Opens the explainer as a bottom sheet (triggered by the in-card button).
  void _showHowItWorks() {
    final cohort = _cohort;
    final promote = (cohort?['promoteCount'] as num?)?.toInt() ?? 7;
    final demote = (cohort?['demoteCount'] as num?)?.toInt() ?? 7;
    // Bronze can't drop (demote == 0) and Legend can't climb (promote == 0), so
    // tailor the rule rather than printing "the bottom 0 drop down".
    final String rule;
    if (promote > 0 && demote > 0) {
      rule = 'Most steps wins. Finish in the top $promote to move up a tier; '
          'the bottom $demote drop down.';
    } else if (demote == 0) {
      rule = 'Most steps wins. Finish in the top $promote to move up a tier — '
          'Bronze is the bottom, so you can only climb.';
    } else {
      rule = 'Most steps wins. The bottom $demote drop a tier — Legend is the '
          'top, so hold your spot to defend it.';
    }
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 16),
            decoration: BoxDecoration(
              color: AppColors.parchment,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.parchmentBorder, width: 2),
            ),
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.help_outline_rounded,
                      size: 20,
                      color: AppColors.textDark,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'How Ranked works',
                      style: PixelText.title(size: 18, color: AppColors.textDark),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      icon: const Icon(Icons.close_rounded),
                      color: AppColors.textMid,
                      iconSize: 20,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const _HowItWorksLine(
                  icon: Icons.groups_rounded,
                  text: 'Each week you’re matched with ~30 walkers at your level.',
                ),
                _HowItWorksLine(
                  icon: Icons.directions_walk_rounded,
                  text: rule,
                ),
                const _HowItWorksLine(
                  icon: Icons.refresh_rounded,
                  text:
                      'Resets every Monday — fresh group, fresh shot. Climb from '
                      'Bronze to Legend.',
                ),
                const SizedBox(height: 14),
                _buildTierLadderStrip(),
              ],
            ),
          ),
        );
      },
    );
  }

  // The six-tier ladder strip: where the user's home tier sits on the climb.
  Widget _buildTierLadderStrip() {
    if (_v2Tiers.isEmpty) return const SizedBox.shrink();
    final myKey = _v2Me?['tier'] as String?;
    return Row(
      children: [
        for (final t in _v2Tiers)
          Expanded(
            child: Opacity(
              opacity: t['key'] == myKey ? 1 : 0.4,
              child: Column(
                children: [
                  TierMedal(
                    tier: rankedTierFromKey(t['key'] as String?),
                    size: t['key'] == myKey ? 38 : 28,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    (t['label'] as String? ?? '').toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PixelText.body(
                      size: 7,
                      color: t['key'] == myKey
                          ? AppColors.textDark
                          : AppColors.textMid,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildHero() {
    final me = _currentUser;
    final ranked = me != null && me['ranked'] == true;

    if (!ranked) {
      return Column(
        children: [
          SizedBox(
            height: 188,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                Positioned.fill(
                  top: 10,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment.topRight,
                        radius: 0.95,
                        colors: [
                          AppColors.accent.withValues(alpha: 0.16),
                          AppColors.parchment.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  child: CustomPaint(
                    size: const Size(128, 116),
                    painter: _RankShieldPainter(
                      color: AppColors.parchmentBorder,
                    ),
                  ),
                ),
                const Positioned(top: 18, child: _CrownedCapybara(size: 74)),
                const Positioned(top: 104, child: _RankRibbon(label: 'JOIN')),
                Positioned(
                  top: 144,
                  child: Column(
                    children: [
                      Text(
                        'UNRANKED',
                        style: PixelText.title(
                          size: 27,
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Not ranked yet',
                        style: PixelText.body(
                          size: 11,
                          color: AppColors.textMid,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: const [
              Expanded(
                child: _HeroMetric(
                  value: '5K',
                  label: 'STEP DAY',
                  accent: AppColors.accent,
                  strong: true,
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: _HeroMetric(
                  value: '0',
                  label: 'RP',
                  accent: AppColors.textDark,
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: _HeroMetric(
                  value: '--',
                  label: 'RANK',
                  accent: AppColors.textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const _TierProgressLine(
            progress: 0.08,
            label: 'Walk 5,000+ steps to enter',
          ),
        ],
      );
    }

    final tier = rankedTierFromKey(me['tier'] as String?);
    final division = (me['division'] as num?)?.toInt();
    final points = (me['points'] as num?)?.toInt() ?? 0;
    final rank = (me['rank'] as num?)?.toInt();
    final reward = _rewardByTier[tier] ?? 0;
    final tierText = romanDivision(division).isEmpty
        ? tier.label.toUpperCase()
        : '${tier.label.toUpperCase()} ${romanDivision(division)}';

    return Column(
      children: [
        SizedBox(
          height: 176,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              Positioned.fill(
                top: 10,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.topRight,
                      radius: 0.95,
                      colors: [
                        tier.color.withValues(alpha: 0.28),
                        AppColors.parchment.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(top: 6, child: TierMedal(tier: tier, size: 132)),
              Positioned(
                top: 148,
                child: Text(
                  tierText,
                  style: PixelText.title(size: 28, color: tier.color),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _HeroStat(
                value: '$points',
                label: 'RANKED POINTS',
                color: tier.color,
              ),
            ),
            Expanded(
              child: _HeroStat(
                value: rank != null ? '$rank' : '--',
                label: 'GLOBAL RANK',
                color: AppColors.textDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _TierProgressLine(
          progress: _tierProgress(tier, points),
          label: _rankStatus(tier, points),
        ),
        if (reward > 0) ...[
          const SizedBox(height: 8),
          _RewardLine(label: 'Finish ${tier.label}', coins: reward),
        ],
      ],
    );
  }

  Widget _buildLadder() {
    final rows = <_RankedRow>[
      for (final e in _ladder) _rowFromEntry(e, isMe: _isMe(e['userId'])),
    ];

    final pinnedMe = _buildPinnedMeRow(rows);
    final podiumRows = rows.take(3).toList();
    final bodyRows = rows.skip(3).toList();

    final counts = <RankedTier, int>{};
    for (final row in rows) {
      counts[row.tier] = (counts[row.tier] ?? 0) + 1;
    }

    final children = <Widget>[
      _LadderTitle(onFriendsTap: () {}),
      if (podiumRows.isNotEmpty) ...[
        const SizedBox(height: 8),
        _Podium(rows: podiumRows),
        const SizedBox(height: 8),
      ],
    ];

    RankedTier? section;
    int rowIndex = 0;
    for (final row in bodyRows) {
      if (row.tier != section) {
        section = row.tier;
        children.add(
          _TierSectionHeader(
            tier: row.tier,
            count: counts[row.tier] ?? 0,
            reward: _rewardByTier[row.tier] ?? 0,
          ),
        );
      }
      children.add(_buildRowTile(row, rowIndex, grouped: true));
      rowIndex++;
    }

    if (pinnedMe != null) {
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            '· · ·',
            textAlign: TextAlign.center,
            style: PixelText.title(size: 14, color: AppColors.textMid),
          ),
        ),
      );
      children.add(
        _TierSectionHeader(
          tier: pinnedMe.tier,
          count: pinnedMe.rank ?? 0,
          reward: _rewardByTier[pinnedMe.tier] ?? 0,
          rankPrefix: '#',
        ),
      );
      children.add(_buildRowTile(pinnedMe, rowIndex));
    }

    return Column(children: children);
  }

  // The current user's own row, only when they're ranked but absent from the
  // visible ladder window (so "you are Bronze III, #412" still shows).
  _RankedRow? _buildPinnedMeRow(List<_RankedRow> rows) {
    final me = _currentUser;
    if (me == null || me['ranked'] != true) return null;
    if (rows.any((r) => r.isMe)) return null;
    return _RankedRow(
      rank: (me['rank'] as num?)?.toInt(),
      userId: widget.authService.userId,
      displayName: widget.authService.displayName ?? 'You',
      profilePhotoUrl: null,
      points: (me['points'] as num?)?.toInt() ?? 0,
      tier: rankedTierFromKey(me['tier'] as String?),
      division: (me['division'] as num?)?.toInt(),
      isMe: true,
    );
  }

  bool _isMe(Object? userId) =>
      userId is String && userId == widget.authService.userId;

  _RankedRow _rowFromEntry(Map<String, dynamic> e, {required bool isMe}) {
    return _RankedRow(
      rank: (e['rank'] as num?)?.toInt(),
      userId: e['userId'] as String?,
      displayName: e['displayName'] as String? ?? 'Anonymous',
      profilePhotoUrl: e['profilePhotoUrl'] as String?,
      points: (e['points'] as num?)?.toInt() ?? 0,
      tier: rankedTierFromKey(e['tier'] as String?),
      division: (e['division'] as num?)?.toInt(),
      isMe: isMe,
      equippedAccessories:
          (e['equippedAccessories'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .toList() ??
          const [],
    );
  }

  Widget _buildRowTile(_RankedRow row, int index, {bool grouped = false}) {
    final rankLabel = row.rank != null ? '${row.rank}' : '--';
    final progress = _tierProgress(row.tier, row.points);
    final backgroundColor = row.isMe
        ? AppColors.accent.withValues(alpha: 0.14)
        : AppColors.parchment;

    final content = Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: row.isMe
              ? AppColors.accent.withValues(alpha: 0.45)
              : AppColors.parchmentBorder.withValues(alpha: 0.6),
          width: row.isMe ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              rankLabel,
              textAlign: TextAlign.center,
              style: PixelText.body(size: 12, color: AppColors.textMid),
            ),
          ),
          const SizedBox(width: 8),
          AppAvatar(
            name: row.displayName,
            imageUrl: row.profilePhotoUrl,
            size: 34,
            isUser: row.isMe,
            borderColor: row.isMe ? AppColors.accent : row.tier.color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  atName(row.displayName),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PixelText.body(
                    size: 13,
                    color: row.isMe ? AppColors.accent : AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: AppColors.parchmentBorder.withValues(
                      alpha: 0.55,
                    ),
                    color: row.tier.color,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (!grouped)
            TierBadge(tier: row.tier, division: row.division)
          else if (row.division != null)
            _DivisionPill(division: row.division!, color: row.tier.color)
          else
            const SizedBox(width: 28),
          const SizedBox(width: 8),
          SizedBox(
            width: 44,
            child: Text(
              '${row.points}',
              textAlign: TextAlign.right,
              style: PixelText.title(
                size: 13,
                color: row.isMe ? AppColors.accent : AppColors.textDark,
              ),
            ),
          ),
        ],
      ),
    );

    final userId = row.userId;
    if (row.isMe || userId == null || userId.isEmpty) return content;

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () => showFriendRequestSheet(
          context: context,
          authService: widget.authService,
          backendApiService: _api,
          userId: userId,
          displayName: row.displayName,
          profilePhotoUrl: row.profilePhotoUrl,
        ),
        child: content,
      ),
    );
  }
}

// ── Ladder row ───────────────────────────────────────────────────────────────

class _RankedRow {
  final int? rank;
  final String? userId;
  final String displayName;
  final String? profilePhotoUrl;
  final int points;
  final RankedTier tier;
  final int? division;
  final bool isMe;
  final List<Map<String, dynamic>> equippedAccessories;

  const _RankedRow({
    required this.rank,
    required this.userId,
    required this.displayName,
    required this.profilePhotoUrl,
    required this.points,
    required this.tier,
    required this.division,
    this.isMe = false,
    this.equippedAccessories = const [],
  });
}

class _TierSectionHeader extends StatelessWidget {
  const _TierSectionHeader({
    required this.tier,
    required this.count,
    this.reward = 0,
    this.rankPrefix = '',
  });

  final RankedTier tier;
  final int count;
  final int reward;
  final String rankPrefix;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
      child: Row(
        children: [
          TierMedal(tier: tier, size: 18),
          const SizedBox(width: 6),
          Text(
            tier.label.toUpperCase(),
            style: PixelText.title(size: 13, color: AppColors.textDark),
          ),
          const SizedBox(width: 6),
          Text(
            '$rankPrefix$count',
            style: PixelText.body(size: 12, color: AppColors.textMid),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 2,
              color: tier.color.withValues(alpha: 0.35),
            ),
          ),
          if (reward > 0) ...[
            const SizedBox(width: 8),
            const Icon(
              Icons.paid_rounded,
              size: 13,
              color: AppColors.medalGold,
            ),
            const SizedBox(width: 3),
            Text(
              '$reward',
              style: PixelText.body(size: 12, color: AppColors.textMid),
            ),
          ],
        ],
      ),
    );
  }
}

/// A single labelled cutline in the group list: "everyone above this moves up"
/// (green) or "everyone below this drops" (clay).
class _LineMarker extends StatelessWidget {
  const _LineMarker({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
      child: Row(
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(label, style: PixelText.body(size: 9, color: color)),
          const SizedBox(width: 8),
          Expanded(
            child: Container(height: 2, color: color.withValues(alpha: 0.45)),
          ),
        ],
      ),
    );
  }
}

/// "…" gap shown between non-contiguous rows in the collapsed group view.
class _GapRow extends StatelessWidget {
  const _GapRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        '· · ·',
        textAlign: TextAlign.center,
        style: PixelText.title(size: 13, color: AppColors.textMid),
      ),
    );
  }
}

/// One bullet line in the "How Ranked works" explainer.
class _HowItWorksLine extends StatelessWidget {
  const _HowItWorksLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: PixelText.body(size: 12, color: AppColors.textDark),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small rounded status chip in the hero ("MOVING UP" / "AT RISK" / …).
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.bg, required this.fg});

  final String label;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: PixelText.body(size: 11, color: fg)),
    );
  }
}

/// Horizontal "where do I sit" bar: a clay drop segment on the left, a neutral
/// hold segment in the middle, a green move-up segment on the right, with a
/// marker at the user's position (rank 1 = far right, last = far left).
class _PositionBar extends StatelessWidget {
  const _PositionBar({
    required this.rank,
    required this.size,
    required this.promote,
    required this.demote,
  });

  final int rank;
  final int size;
  final int promote;
  final int demote;

  static const _green = Color(0xFF3E8E4B);
  static const _clay = Color(0xFFB4503C);

  @override
  Widget build(BuildContext context) {
    final total = size <= 0 ? 1 : size;
    final hold = (total - promote - demote).clamp(0, total);
    // rank 1 -> 1.0 (far right / best), rank `size` -> 0.0 (far left).
    final frac = size <= 1 ? 1.0 : (size - rank) / (size - 1);

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        const markerW = 14.0;
        final markerLeft = (frac * (w - markerW)).clamp(0.0, w - markerW);
        return SizedBox(
          height: 26,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 9,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: Row(
                    children: [
                      if (demote > 0)
                        Expanded(
                          flex: demote,
                          child: Container(
                            height: 8,
                            color: _clay.withValues(alpha: 0.55),
                          ),
                        ),
                      if (hold > 0)
                        Expanded(
                          flex: hold,
                          child: Container(
                            height: 8,
                            color: AppColors.parchmentBorder,
                          ),
                        ),
                      if (promote > 0)
                        Expanded(
                          flex: promote,
                          child: Container(
                            height: 8,
                            color: _green.withValues(alpha: 0.6),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: markerLeft,
                top: 3,
                child: Container(
                  width: markerW,
                  height: markerW,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: const [
                      BoxShadow(color: Color(0x33000000), blurRadius: 3),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Plain-language status derived from the cohort + the user's standing.
class _V2Status {
  const _V2Status({
    required this.rank,
    required this.size,
    required this.promote,
    required this.demote,
    required this.kind,
    required this.gapUp,
    required this.gapSafe,
    required this.leadOverCut,
    required this.upTier,
    required this.downTier,
    required this.promoCoins,
    required this.projectedCoins,
    required this.tier,
  });

  final int rank;
  final int size;
  final int promote;
  final int demote;
  final String kind; // 'top' | 'promo' | 'safe' | 'danger'
  final int? gapUp; // steps to reach the move-up line
  final int? gapSafe; // steps to climb out of the drop zone
  final int? leadOverCut; // lead over the move-up line when already promoting
  final String? upTier;
  final String? downTier;
  final int promoCoins;
  final int projectedCoins;
  final RankedTier tier;
}

class _DivisionPill extends StatelessWidget {
  const _DivisionPill({required this.division, required this.color});

  final int division;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color, width: 1),
      ),
      child: Text(
        romanDivision(division),
        style: PixelText.title(size: 10, color: AppColors.textDark),
      ),
    );
  }
}

class _RewardLine extends StatelessWidget {
  const _RewardLine({required this.label, required this.coins});

  final String label;
  final int coins;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.paid_rounded, size: 15, color: AppColors.medalGold),
        const SizedBox(width: 6),
        Text(
          '$label → $coins coins',
          style: PixelText.body(size: 13, color: AppColors.textMid),
        ),
      ],
    );
  }
}

class _SeasonCountdown extends StatelessWidget {
  const _SeasonCountdown({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          title,
          style: PixelText.title(size: 13, color: AppColors.medalGold),
        ),
      ],
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({
    required this.value,
    required this.label,
    required this.accent,
    this.strong = false,
  });

  final String value;
  final String label;
  final Color accent;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.parchment,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accent, width: strong ? 1.6 : 1.1),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PixelText.title(size: 17, color: AppColors.textDark),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PixelText.body(size: 7.5, color: AppColors.textMid),
            ),
          ],
        ),
      ),
    );
  }
}

/// A borderless hero stat: a big number sitting on the background with a small
/// caption under it (no card/frame).
class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.value,
    required this.label,
    required this.color,
  });

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: PixelText.title(size: 34, color: color),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: PixelText.body(size: 9.5, color: AppColors.textMid),
        ),
      ],
    );
  }
}

class _TierProgressLine extends StatelessWidget {
  const _TierProgressLine({required this.progress, required this.label});

  final double progress;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              backgroundColor: AppColors.parchmentBorder.withValues(alpha: 0.8),
              color: AppColors.medalGold,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(label, style: PixelText.body(size: 10, color: AppColors.textDark)),
      ],
    );
  }
}

class _RankRibbon extends StatelessWidget {
  const _RankRibbon({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RibbonPainter(),
      child: SizedBox(
        width: 116,
        height: 40,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              label,
              style: PixelText.title(size: 16, color: AppColors.textDark),
            ),
          ),
        ),
      ),
    );
  }
}

class _CrownedCapybara extends StatelessWidget {
  const _CrownedCapybara({this.size = 64});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size + 16,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Positioned(top: 18, child: _CapybaraFrame(size: size)),
          Positioned(
            top: 0,
            child: CustomPaint(
              size: Size(size * 0.46, size * 0.34),
              painter: _CrownPainter(),
            ),
          ),
        ],
      ),
    );
  }
}

class _CapybaraFrame extends StatelessWidget {
  const _CapybaraFrame({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ClipRect(
        child: OverflowBox(
          maxWidth: double.infinity,
          alignment: Alignment.topLeft,
          child: Image.asset(
            'assets/images/capybara_walk_right.png',
            width: size * 6,
            height: size,
            filterQuality: FilterQuality.none,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}

class _LadderTitle extends StatelessWidget {
  const _LadderTitle({required this.onFriendsTap});

  final VoidCallback onFriendsTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(
          Icons.emoji_events_outlined,
          size: 15,
          color: AppColors.textDark,
        ),
        const SizedBox(width: 8),
        Text(
          'Global ladder',
          style: PixelText.body(size: 14, color: AppColors.textDark),
        ),
        const Spacer(),
        TextButton(
          onPressed: onFriendsTap,
          style: TextButton.styleFrom(
            minimumSize: Size.zero,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            'FRIENDS',
            style: PixelText.body(size: 9, color: AppColors.textMid),
          ),
        ),
      ],
    );
  }
}

class _Podium extends StatelessWidget {
  const _Podium({required this.rows});

  final List<_RankedRow> rows;

  _RankedRow? _rank(int rank) {
    for (final row in rows) {
      if (row.rank == rank) return row;
    }
    return rows.length >= rank ? rows[rank - 1] : null;
  }

  @override
  Widget build(BuildContext context) {
    final first = _rank(1);
    final second = _rank(2);
    final third = _rank(3);

    return SizedBox(
      height: 184,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: _PodiumPlace(row: second, place: 2, height: 54)),
          const SizedBox(width: 8),
          Expanded(child: _PodiumPlace(row: first, place: 1, height: 72)),
          const SizedBox(width: 8),
          Expanded(child: _PodiumPlace(row: third, place: 3, height: 46)),
        ],
      ),
    );
  }
}

class _PodiumPlace extends StatelessWidget {
  const _PodiumPlace({
    required this.row,
    required this.place,
    required this.height,
  });

  final _RankedRow? row;
  final int place;
  final double height;

  @override
  Widget build(BuildContext context) {
    final entry = row;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (entry != null) ...[
          AnimatedCapybaraWithAccessories(
            accessories: entry.equippedAccessories,
            size: place == 1 ? 54 : 44,
          ),
          const SizedBox(height: 4),
          Text(
            atName(entry.displayName),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PixelText.body(size: 10, color: AppColors.textDark),
          ),
          Text(
            '${entry.points}',
            style: PixelText.body(size: 9, color: AppColors.skyBand1),
          ),
          Text(
            entry.tier.label.toUpperCase(),
            style: PixelText.body(size: 7.5, color: AppColors.textMid),
          ),
        ] else
          const SizedBox(height: 64),
        const SizedBox(height: 4),
        Container(
          height: height,
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF42B3DD), Color(0xFF247FA1)],
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            border: Border.all(color: const Color(0xFF16627E), width: 1),
          ),
          child: Center(
            child: Text(
              '$place',
              style: PixelText.title(size: 18, color: AppColors.textDark),
            ),
          ),
        ),
      ],
    );
  }
}

class _RankShieldPainter extends CustomPainter {
  const _RankShieldPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final shadow = Paint()
      ..color = color.withValues(alpha: 0.14)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height * 0.62),
        width: size.width * 1.16,
        height: size.height * 0.95,
      ),
      shadow,
    );

    final path = Path()
      ..moveTo(size.width * 0.12, size.height * 0.08)
      ..lineTo(size.width * 0.88, size.height * 0.08)
      ..lineTo(size.width * 0.88, size.height * 0.43)
      ..quadraticBezierTo(
        size.width * 0.84,
        size.height * 0.74,
        size.width * 0.5,
        size.height * 0.95,
      )
      ..quadraticBezierTo(
        size.width * 0.16,
        size.height * 0.74,
        size.width * 0.12,
        size.height * 0.43,
      )
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.24),
            color.withValues(alpha: 0.54),
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0xFF9F7620),
    );
  }

  @override
  bool shouldRepaint(covariant _RankShieldPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _RibbonPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * 0.08, size.height * 0.24)
      ..lineTo(size.width * 0.92, size.height * 0.24)
      ..lineTo(size.width * 0.84, size.height * 0.95)
      ..lineTo(size.width * 0.16, size.height * 0.95)
      ..close();
    final tailLeft = Path()
      ..moveTo(size.width * 0.08, size.height * 0.24)
      ..lineTo(0, size.height * 0.95)
      ..lineTo(size.width * 0.16, size.height * 0.95);
    final tailRight = Path()
      ..moveTo(size.width * 0.92, size.height * 0.24)
      ..lineTo(size.width, size.height * 0.95)
      ..lineTo(size.width * 0.84, size.height * 0.95);

    final fill = Paint()..color = const Color(0xFFD6A72F);
    canvas
      ..drawPath(tailLeft, fill)
      ..drawPath(tailRight, fill)
      ..drawPath(path, Paint()..color = const Color(0xFFE9BD48));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = const Color(0xFF9F7620),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CrownPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final crown = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width * 0.12, size.height * 0.26)
      ..lineTo(size.width * 0.33, size.height * 0.58)
      ..lineTo(size.width * 0.5, 0)
      ..lineTo(size.width * 0.67, size.height * 0.58)
      ..lineTo(size.width * 0.88, size.height * 0.26)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(crown, Paint()..color = const Color(0xFFE7BD46));
    canvas.drawPath(
      crown,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = const Color(0xFF9B721D),
    );

    final jewelPaint = Paint()..color = const Color(0xFFFFED92);
    for (final x in [0.12, 0.5, 0.88]) {
      canvas.drawCircle(
        Offset(size.width * x, x == 0.5 ? 2.5 : size.height * 0.25),
        2.4,
        jewelPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ComingSoonPanel extends StatelessWidget {
  const _ComingSoonPanel();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 32),
      child: Column(
        children: [
          Icon(
            Icons.shield_outlined,
            size: 34,
            color: AppColors.textMid.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 8),
          Text(
            'Ranked is coming soon',
            style: PixelText.title(size: 18, color: AppColors.textMid),
          ),
          const SizedBox(height: 6),
          Text(
            'Keep walking — your steps will count toward the ladder.',
            textAlign: TextAlign.center,
            style: PixelText.body(size: 13, color: AppColors.textMid),
          ),
        ],
      ),
    );
  }
}

class _HeroSkeleton extends StatelessWidget {
  const _HeroSkeleton();

  @override
  Widget build(BuildContext context) {
    return GameContainer(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      frameColor: AppColors.accent,
      surfaceColor: AppColors.parchment,
      child: Column(
        children: [
          Container(
            width: 150,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.parchmentBorder.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: 120,
            height: 18,
            decoration: BoxDecoration(
              color: AppColors.parchmentBorder.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ],
      ),
    );
  }
}
