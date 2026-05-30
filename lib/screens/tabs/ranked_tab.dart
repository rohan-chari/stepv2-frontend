import 'package:flutter/material.dart';

import '../../models/loadable.dart';
import '../../services/auth_service.dart';
import '../../services/backend_api_service.dart';
import '../../styles.dart';
import '../../widgets/app_avatar.dart';
import '../../widgets/friend_request_sheet.dart';
import '../../widgets/game_container.dart';
import '../../widgets/loading_skeleton.dart';
import '../../widgets/tier_badge.dart';

/// Ranked ladder for the active season. Self-fetching like [LeaderboardTab];
/// `refreshNonce` is bumped by the shell when the tab is revealed so it
/// re-syncs. Degrades safely: an old backend (404 on `/ranked`) or no active
/// season renders a calm "coming soon" state rather than an error, and a user
/// with no score yet sees an explicit "not ranked" hero — never a fake number.
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
  List<Map<String, dynamic>> _ladder = [];
  Map<String, dynamic>? _currentUser;
  Map<String, dynamic>? _season;
  Map<RankedTier, int> _rewardByTier = {};
  // True when the backend has no Ranked endpoint yet (old prod serving a newer
  // app). Treated as "coming soon", not an error.
  bool _unavailable = false;

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
      final data = await _api.fetchRanked(identityToken: token);
      if (!mounted) return;
      setState(() {
        _unavailable = false;
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
      // 404 → this build is newer than the deployed backend. Don't alarm the
      // user; Ranked simply isn't live for them yet.
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
      decoration: const BoxDecoration(color: AppColors.roofEdge),
      child: CustomPaint(
        painter: const ArcadeCheckerPainter(
          drawBottomStripe: false,
          tileColor: Color(0x08FFFFFF),
        ),
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
              _SeasonCountdown(
                title: _seasonSubtitle(),
                caption: _seasonDayCaption(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _seasonLabel() {
    final index = (_season?['index'] as num?)?.toInt();
    return index == null
        ? 'Walk to earn Ranked Points'
        : 'Season $index · climb the ladder by walking';
  }

  int? _seasonDaysLeft() {
    final ends = DateTime.tryParse(_season?['endsAt']?.toString() ?? '');
    if (ends == null) return null;
    final now = DateTime.now();
    if (ends.isBefore(now)) return 0;
    final hours = ends.difference(now).inHours;
    return (hours / 24).ceil();
  }

  String _seasonSubtitle() {
    final days = _seasonDaysLeft();
    if (days == null) return 'Walk to earn Ranked Points';
    if (days > 1) return '$days days left';
    if (days == 1) return '1 day left';
    return 'ends today';
  }

  String _seasonDayCaption() {
    final season = _season;
    if (season == null) return 'DAY 1/30';
    final ends = DateTime.tryParse(season['endsAt']?.toString() ?? '');
    if (ends == null) return 'DAY 1/30';
    final daysLeft = _seasonDaysLeft() ?? 0;
    final totalDays = (season['durationDays'] as num?)?.toInt() ?? 30;
    final elapsed = (totalDays - daysLeft).clamp(1, totalDays);
    return 'DAY $elapsed/$totalDays';
  }

  String _rankStatus(RankedTier tier, int points) {
    final next = switch (tier) {
      RankedTier.bronze => 200,
      RankedTier.silver => 550,
      RankedTier.gold => 1400,
      RankedTier.diamond || RankedTier.unranked => null,
    };
    if (next == null) return 'Top tier';
    return '${next - points > 0 ? next - points : 0} RP to ${_nextTierName(tier)}';
  }

  String _nextTierName(RankedTier tier) => switch (tier) {
    RankedTier.bronze => 'Silver I',
    RankedTier.silver => 'Gold I',
    RankedTier.gold => 'Diamond I',
    RankedTier.diamond || RankedTier.unranked => 'next tier',
  };

  double _tierProgress(RankedTier tier, int points) {
    final (floor, next) = switch (tier) {
      RankedTier.bronze => (0, 200),
      RankedTier.silver => (200, 550),
      RankedTier.gold => (550, 1400),
      RankedTier.diamond => (1400, 1800),
      RankedTier.unranked => (0, 200),
    };
    return ((points - floor) / (next - floor)).clamp(0.08, 1).toDouble();
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
        _buildHero(),
        if (_ladder.isNotEmpty) ...[const SizedBox(height: 14), _buildLadder()],
      ],
    );
  }

  Widget _buildHero() {
    final me = _currentUser;
    final ranked = me != null && me['ranked'] == true;

    if (!ranked) {
      return GameContainer(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        frameColor: AppColors.accent,
        surfaceColor: AppColors.parchment,
        child: Column(
          children: [
            Icon(
              Icons.shield_outlined,
              size: 34,
              color: AppColors.textMid.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 8),
            Text(
              'Not ranked yet',
              style: PixelText.title(size: 18, color: AppColors.textDark),
            ),
            const SizedBox(height: 4),
            Text(
              'Walk 5,000+ steps in a day to join this season’s ladder.',
              textAlign: TextAlign.center,
              style: PixelText.body(size: 13, color: AppColors.textMid),
            ),
          ],
        ),
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
          height: 190,
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
              Positioned(
                top: 0,
                child: CustomPaint(
                  size: const Size(128, 116),
                  painter: _RankShieldPainter(color: tier.color),
                ),
              ),
              const Positioned(top: 18, child: _CrownedCapybara(size: 74)),
              Positioned(
                top: 104,
                child: _RankRibbon(label: rank != null ? '#$rank' : '--'),
              ),
              Positioned(
                top: 144,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      tierText,
                      style: PixelText.title(size: 28, color: tier.color),
                    ),
                    if (division != null) ...[
                      const SizedBox(width: 8),
                      _DivisionPill(division: division, color: tier.color),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        Row(
          children: [
            Expanded(
              child: _HeroMetric(
                value: '$points',
                label: 'RP',
                accent: tier.color,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _HeroMetric(
                value: rank != null ? '$rank' : '--',
                label: 'GLOBAL RANK',
                accent: AppColors.textDark,
                strong: true,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _HeroMetric(
                value: '${_ladder.length}',
                label: 'OF RANKED',
                accent: AppColors.textDark,
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
                  row.displayName,
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

  const _RankedRow({
    required this.rank,
    required this.userId,
    required this.displayName,
    required this.profilePhotoUrl,
    required this.points,
    required this.tier,
    required this.division,
    this.isMe = false,
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
          Icon(Icons.shield_rounded, size: 15, color: tier.color),
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
  const _SeasonCountdown({required this.title, required this.caption});

  final String title;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          title,
          style: PixelText.title(size: 13, color: AppColors.medalGold),
        ),
        const SizedBox(height: 3),
        Text(
          caption,
          style: PixelText.body(
            size: 9,
            color: AppColors.parchment.withValues(alpha: 0.86),
          ),
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
      height: 168,
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
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              AppAvatar(
                name: entry.displayName,
                imageUrl: entry.profilePhotoUrl,
                size: place == 1 ? 46 : 38,
                isUser: entry.isMe,
                borderColor: entry.tier.color,
              ),
              if (place == 1)
                Positioned(
                  top: -18,
                  child: CustomPaint(
                    size: const Size(28, 22),
                    painter: _CrownPainter(),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            entry.displayName,
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
