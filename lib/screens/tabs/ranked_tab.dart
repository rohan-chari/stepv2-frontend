import 'package:flutter/material.dart';

import '../../models/loadable.dart';
import '../../services/auth_service.dart';
import '../../services/backend_api_service.dart';
import '../../styles.dart';
import '../../widgets/app_avatar.dart';
import '../../widgets/friend_request_sheet.dart';
import '../../widgets/game_container.dart';
import '../../widgets/loading_skeleton.dart';

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
  // True when the backend has no Ranked endpoint yet (old prod serving a newer
  // app). Treated as "coming soon", not an error.
  bool _unavailable = false;

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
        setState(() => _state = Loadable.error(
              'Not signed in.',
              data: previous.isEmpty ? null : previous,
            ));
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
      setState(() => _state = Loadable.error(
            e.toString(),
            data: previous.isEmpty ? null : previous,
          ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _state = Loadable.error(
            e.toString(),
            data: previous.isEmpty ? null : previous,
          ));
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
              slivers: [
                SliverToBoxAdapter(child: _buildShell()),
              ],
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
            padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
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
          padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'RANKED',
                style: PixelText.title(size: 30, color: AppColors.parchment),
              ),
              const SizedBox(height: 4),
              Text(
                _seasonSubtitle(),
                style: PixelText.body(
                  size: 13,
                  color: AppColors.parchment.withValues(alpha: 0.92),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _seasonSubtitle() {
    final season = _season;
    if (season == null) return 'Walk to earn Ranked Points';
    final index = (season['index'] as num?)?.toInt();
    final ends = DateTime.tryParse(season['endsAt']?.toString() ?? '');
    final parts = <String>[];
    if (index != null) parts.add('Season $index');
    if (ends != null) {
      final days = ends.difference(DateTime.now()).inDays;
      if (days > 1) {
        parts.add('ends in $days days');
      } else if (days == 1) {
        parts.add('ends tomorrow');
      } else if (!ends.isBefore(DateTime.now())) {
        parts.add('ends today');
      }
    }
    return parts.isEmpty ? 'Ranked season' : parts.join(' · ');
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
        if (_ladder.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildLadder(),
        ],
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
            Icon(Icons.shield_outlined,
                size: 34, color: AppColors.textMid.withValues(alpha: 0.7)),
            const SizedBox(height: 8),
            Text('Not ranked yet',
                style: PixelText.title(size: 18, color: AppColors.textDark)),
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

    final tier = _tierFromKey(me['tier'] as String?);
    final division = (me['division'] as num?)?.toInt();
    final points = (me['points'] as num?)?.toInt() ?? 0;
    final rank = (me['rank'] as num?)?.toInt();

    return GameContainer(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      frameColor: tier.color,
      surfaceColor: AppColors.parchment,
      child: Column(
        children: [
          _TierBadge(tier: tier, division: division, large: true),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _HeroStat(label: 'RANK', value: rank != null ? '#$rank' : '--'),
              _HeroStat(label: 'RP', value: '$points'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLadder() {
    final rows = <_RankedRow>[
      for (final e in _ladder) _rowFromEntry(e, isMe: _isMe(e['userId'])),
    ];

    final pinnedMe = _buildPinnedMeRow(rows);

    final children = <Widget>[];
    for (int i = 0; i < rows.length; i++) {
      children.add(_buildRowTile(rows[i], i));
    }
    if (pinnedMe != null) {
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            '· · ·',
            textAlign: TextAlign.center,
            style: PixelText.title(size: 14, color: AppColors.textMid),
          ),
        ),
      );
      children.add(_buildRowTile(pinnedMe, rows.length));
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Column(children: children),
    );
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
      tier: _tierFromKey(me['tier'] as String?),
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
      tier: _tierFromKey(e['tier'] as String?),
      division: (e['division'] as num?)?.toInt(),
      isMe: isMe,
    );
  }

  Widget _buildRowTile(_RankedRow row, int index) {
    final rankLabel = row.rank != null ? '${row.rank}' : '--';
    final stripeColor = index.isOdd
        ? AppColors.parchmentDark.withValues(alpha: 0.45)
        : Colors.transparent;
    final backgroundColor = row.isMe
        ? AppColors.accent.withValues(alpha: 0.16)
        : stripeColor;

    final content = Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        border: row.isMe
            ? const Border(left: BorderSide(color: AppColors.accent, width: 3))
            : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Text(
              rankLabel,
              textAlign: TextAlign.center,
              style: PixelText.title(size: 14, color: AppColors.textDark),
            ),
          ),
          const SizedBox(width: 8),
          AppAvatar(
            name: row.displayName,
            imageUrl: row.profilePhotoUrl,
            size: 32,
            isUser: row.isMe,
            borderColor: row.isMe ? AppColors.accent : Colors.white,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    row.displayName,
                    overflow: TextOverflow.ellipsis,
                    style: PixelText.body(
                      size: 16,
                      color: row.isMe ? AppColors.accent : AppColors.textDark,
                    ),
                  ),
                ),
                if (row.isMe) ...[
                  const SizedBox(width: 6),
                  Text('(you)',
                      style:
                          PixelText.pill(size: 10.5, color: AppColors.accent)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          _TierBadge(tier: row.tier, division: row.division),
          const SizedBox(width: 8),
          SizedBox(
            width: 52,
            child: Text(
              '${row.points}',
              textAlign: TextAlign.right,
              style: PixelText.title(
                size: 15,
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

// ── Tier model ───────────────────────────────────────────────────────────────

enum _Tier { bronze, silver, gold, diamond, unranked }

_Tier _tierFromKey(String? key) {
  switch (key) {
    case 'BRONZE':
      return _Tier.bronze;
    case 'SILVER':
      return _Tier.silver;
    case 'GOLD':
      return _Tier.gold;
    case 'DIAMOND':
      return _Tier.diamond;
    default:
      return _Tier.unranked;
  }
}

extension on _Tier {
  String get label => switch (this) {
        _Tier.bronze => 'Bronze',
        _Tier.silver => 'Silver',
        _Tier.gold => 'Gold',
        _Tier.diamond => 'Diamond',
        _Tier.unranked => 'Unranked',
      };

  Color get color => switch (this) {
        _Tier.bronze => AppColors.medalBronze,
        _Tier.silver => AppColors.medalSilver,
        _Tier.gold => AppColors.medalGold,
        _Tier.diamond => const Color(0xFF49B6E0),
        _Tier.unranked => AppColors.textMid,
      };
}

String _roman(int? division) => switch (division) {
      1 => 'I',
      2 => 'II',
      3 => 'III',
      _ => '',
    };

class _RankedRow {
  final int? rank;
  final String? userId;
  final String displayName;
  final String? profilePhotoUrl;
  final int points;
  final _Tier tier;
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

class _TierBadge extends StatelessWidget {
  const _TierBadge({required this.tier, this.division, this.large = false});

  final _Tier tier;
  final int? division;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final roman = _roman(division);
    final text = roman.isEmpty ? tier.label : '${tier.label} $roman';

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 14 : 8,
        vertical: large ? 8 : 4,
      ),
      decoration: BoxDecoration(
        color: tier.color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(large ? 10 : 7),
        border: Border.all(color: tier.color, width: large ? 2 : 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shield_rounded,
              size: large ? 20 : 12, color: tier.color),
          SizedBox(width: large ? 8 : 4),
          Text(
            large ? text.toUpperCase() : text,
            style: PixelText.title(
              size: large ? 18 : 10,
              color: AppColors.textDark,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: PixelText.title(size: 22, color: AppColors.accent)),
        const SizedBox(height: 2),
        Text(label, style: PixelText.body(size: 11, color: AppColors.textMid)),
      ],
    );
  }
}

class _ComingSoonPanel extends StatelessWidget {
  const _ComingSoonPanel();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 32),
      child: Column(
        children: [
          Icon(Icons.shield_outlined,
              size: 34, color: AppColors.textMid.withValues(alpha: 0.6)),
          const SizedBox(height: 8),
          Text('Ranked is coming soon',
              style: PixelText.title(size: 18, color: AppColors.textMid)),
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
