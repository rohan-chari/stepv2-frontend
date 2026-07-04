import 'package:flutter/material.dart';

import '../../config/animals.dart';
import '../../models/loadable.dart';
import '../../models/step_data.dart';
import '../../services/auth_service.dart';
import '../../services/backend_api_service.dart';
import '../../styles.dart';
import '../../utils/at_name.dart';
import '../../widgets/app_avatar.dart';
import '../../widgets/filter_dropdown.dart';
import '../../widgets/game_container.dart';
import '../../widgets/friend_request_sheet.dart';
import '../../widgets/home_course_track.dart'
    show AnimatedCapybaraWithAccessories;
import '../../widgets/loading_skeleton.dart';
import '../../widgets/pill_button.dart';

enum _LeaderboardType { steps, races }

enum _LeaderboardScope { global, friends }

extension on _LeaderboardScope {
  String get apiValue {
    switch (this) {
      case _LeaderboardScope.global:
        return 'global';
      case _LeaderboardScope.friends:
        return 'friends';
    }
  }

  // Section-header title shown above the podium for the active scope.
  String get boardTitle {
    switch (this) {
      case _LeaderboardScope.global:
        return 'Global Leaderboard';
      case _LeaderboardScope.friends:
        return 'Friends Leaderboard';
    }
  }

  // Intuitive glyph for the compact toggle: a globe for global, people for
  // friends.
  IconData get icon {
    switch (this) {
      case _LeaderboardScope.global:
        return Icons.public_rounded;
      case _LeaderboardScope.friends:
        return Icons.group_rounded;
    }
  }
}

_LeaderboardType _leaderboardTypeFromApi(String apiValue) {
  switch (apiValue) {
    case 'races':
      return _LeaderboardType.races;
    case 'steps':
    default:
      return _LeaderboardType.steps;
  }
}

extension on _LeaderboardType {
  String get apiValue {
    switch (this) {
      case _LeaderboardType.steps:
        return 'steps';
      case _LeaderboardType.races:
        return 'races';
    }
  }

  String get label {
    switch (this) {
      case _LeaderboardType.steps:
        return 'STEPS';
      case _LeaderboardType.races:
        return 'RACES';
    }
  }

  String get emptyTitle {
    switch (this) {
      case _LeaderboardType.steps:
        return 'No steps yet - get walking!';
      case _LeaderboardType.races:
        return 'No race records yet';
    }
  }

  String? get emptySubtitle {
    switch (this) {
      case _LeaderboardType.steps:
        return null;
      case _LeaderboardType.races:
        return 'Complete races to start building a podium record.';
    }
  }

  IconData get emptyIcon {
    switch (this) {
      case _LeaderboardType.steps:
        return Icons.directions_walk;
      case _LeaderboardType.races:
        return Icons.flag_rounded;
    }
  }
}

class LeaderboardTab extends StatefulWidget {
  final AuthService authService;
  final BackendApiService? backendApiService;
  final StepData? stepData;
  final String? displayName;
  final String requestedType;
  final String requestedPeriod;
  final int selectionNonce;
  final VoidCallback? onOpenProfile;
  // Optional tutorial spotlight anchor for the current user's row. Null in the
  // shipped app (the internal _myRowKey is used as before); the tutorial passes
  // a key so its overlay can measure the highlighted "you" row.
  final GlobalKey? tutorialMyRowKey;

  const LeaderboardTab({
    super.key,
    required this.authService,
    this.backendApiService,
    this.stepData,
    this.displayName,
    this.requestedType = 'steps',
    this.requestedPeriod = 'today',
    this.selectionNonce = 0,
    this.onOpenProfile,
    this.tutorialMyRowKey,
  });

  @override
  State<LeaderboardTab> createState() => _LeaderboardTabState();
}

class _LeaderboardTabState extends State<LeaderboardTab> {
  late final BackendApiService _api;
  _LeaderboardType _selectedType = _LeaderboardType.steps;
  String _selectedPeriod = 'today';
  _LeaderboardScope _selectedScope = _LeaderboardScope.global;
  bool _isLoading = true;
  List<Map<String, dynamic>> _top100 = [];
  Map<String, dynamic>? _currentUser;
  Loadable<List<Map<String, dynamic>>> _leaderboardState =
      const Loadable.initial();
  final GlobalKey _myRowKey = GlobalKey();

  static const _periods = [
    ('today', 'TODAY'),
    ('week', 'WEEK'),
    ('month', 'MONTH'),
    ('allTime', 'ALL TIME'),
  ];

  static const _textShadows = [
    Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  @override
  void initState() {
    super.initState();
    _api = widget.backendApiService ?? BackendApiService();
    _selectedType = _leaderboardTypeFromApi(widget.requestedType);
    _selectedPeriod = _selectedType == _LeaderboardType.steps
        ? widget.requestedPeriod
        : 'allTime';
    _loadLeaderboard();
  }

  @override
  void didUpdateWidget(covariant LeaderboardTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectionNonce == oldWidget.selectionNonce) return;

    final requestedType = _leaderboardTypeFromApi(widget.requestedType);
    final requestedPeriod = requestedType == _LeaderboardType.steps
        ? widget.requestedPeriod
        : 'allTime';

    if (requestedType == _selectedType && requestedPeriod == _selectedPeriod) {
      return;
    }

    setState(() {
      _selectedType = requestedType;
      _selectedPeriod = requestedPeriod;
    });
    _loadLeaderboard();
  }

  Future<void> _loadLeaderboard() async {
    final previous = _top100;
    if (mounted) {
      setState(() {
        _isLoading = true;
        _leaderboardState = previous.isEmpty
            ? const Loadable.loading()
            : Loadable.refreshing(previous);
      });
    }

    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _leaderboardState = Loadable.error(
            'Not signed in.',
            data: previous.isEmpty ? null : previous,
          );
        });
      }
      return;
    }

    final requestType = _selectedType;
    final requestPeriod = requestType == _LeaderboardType.steps
        ? _selectedPeriod
        : 'allTime';
    final requestScope = _selectedScope;

    try {
      final data = await _api.fetchLeaderboard(
        identityToken: token,
        type: requestType.apiValue,
        period: requestPeriod,
        scope: requestScope.apiValue,
      );

      if (!mounted ||
          requestType != _selectedType ||
          requestScope != _selectedScope ||
          requestPeriod !=
              (_selectedType == _LeaderboardType.steps
                  ? _selectedPeriod
                  : 'allTime')) {
        return;
      }

      setState(() {
        final top100Raw = data['top100'] as List? ?? [];
        _top100 = top100Raw.cast<Map<String, dynamic>>();
        _currentUser = data['currentUser'] as Map<String, dynamic>?;
        _leaderboardState = Loadable.success(_top100);
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _leaderboardState = Loadable.error(
            e.toString(),
            data: previous.isEmpty ? null : previous,
          );
        });
      }
    }
  }

  void _selectPeriod(String period) {
    if (period == _selectedPeriod) return;
    setState(() => _selectedPeriod = period);
    _loadLeaderboard();
  }

  void _selectType(_LeaderboardType type) {
    if (type == _selectedType) return;
    setState(() => _selectedType = type);
    _loadLeaderboard();
  }

  void _selectScope(_LeaderboardScope scope) {
    if (scope == _selectedScope) return;
    setState(() => _selectedScope = scope);
    _loadLeaderboard();
  }

  String _formatSteps(int steps) {
    if (steps >= 1000) {
      return '${(steps / 1000).toStringAsFixed(1)}k';
    }
    return '$steps';
  }

  String _displayValue(Map<String, dynamic> entry) {
    switch (_selectedType) {
      case _LeaderboardType.steps:
        return _formatSteps((entry['totalSteps'] as num?)?.toInt() ?? 0);
      case _LeaderboardType.races:
        final firsts = entry['firsts'] as int? ?? 0;
        final seconds = entry['seconds'] as int? ?? 0;
        final thirds = entry['thirds'] as int? ?? 0;
        return '1ST $firsts  2ND $seconds  3RD $thirds';
    }
  }

  Widget _buildValueContent(_LeaderboardRow row) {
    if (_selectedType != _LeaderboardType.races) {
      return Text(
        row.valueLabel,
        style: PixelText.title(
          size: _selectedType == _LeaderboardType.races ? 12 : 16,
          color: row.isMe ? AppColors.accent : AppColors.textDark,
        ),
        textAlign: TextAlign.right,
      );
    }

    return _RacePodiumBadges(
      key: Key('leaderboard-race-podiums-${row.displayName}'),
      firsts: row.firsts ?? 0,
      seconds: row.seconds ?? 0,
      thirds: row.thirds ?? 0,
      isMe: row.isMe,
    );
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
            onRefresh: _loadLeaderboard,
            color: AppColors.accent,
            backgroundColor: AppColors.parchment,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Column(children: [_buildLeaderboardShell()]),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLeaderboardShell() {
    return Column(
      children: [
        _buildRankingControls(),
        ColoredBox(
          color: AppColors.parchment,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
            child: _buildLeaderboardState(),
          ),
        ),
      ],
    );
  }

  Widget _buildLeaderboardState() {
    final state = _leaderboardState;
    if (state.shouldShowInitialLoading || (_isLoading && _top100.isEmpty)) {
      return Column(
        children: const [
          _PodiumSkeleton(),
          SizedBox(height: 14),
          ListSkeleton(itemCount: 5, showAvatar: true),
        ],
      );
    }

    if (state.isError && !state.hasData) {
      return LoadErrorPanel(
        title: 'Couldn’t load leaderboard',
        message: 'Check your connection and try again.',
        onRetry: _loadLeaderboard,
      );
    }

    if (_top100.isEmpty) {
      // Keep the scope toggle reachable when the board is empty (e.g. on the
      // Friends scope with no friends yet) — otherwise the user is stranded.
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 2, 6, 0),
            child: _buildScopeHeader(),
          ),
          const SizedBox(height: 6),
          _buildEmptyState(),
        ],
      );
    }

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
        _buildLeaderboardBoard(),
      ],
    );
  }

  Widget _buildTypeTabs() {
    final types = _LeaderboardType.values;

    return Row(
      children: [
        for (int i = 0; i < types.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: PillButton(
              label: types[i].label,
              onPressed: () => _selectType(types[i]),
              variant: types[i] == _selectedType
                  ? PillButtonVariant.secondary
                  : PillButtonVariant.accent,
              fontSize: 11,
              fullWidth: true,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            ),
          ),
        ],
      ],
    );
  }

  // The scope section header for the podium / board: the active scope's title
  // centred in the container, with a compact globe/friends icon toggle pinned
  // to the right.
  Widget _buildScopeHeader() {
    return Stack(
      alignment: Alignment.center,
      children: [
        Center(
          child: Text(
            _selectedScope.boardTitle,
            textAlign: TextAlign.center,
            style: PixelText.title(size: 15, color: AppColors.textDark),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: _ScopeIconToggle(
            selected: _selectedScope,
            onChanged: _selectScope,
          ),
        ),
      ],
    );
  }

  Widget _buildRankingControls() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.roofLight,
        border: Border(bottom: BorderSide(color: AppColors.roofDark, width: 1)),
      ),
      child: CustomPaint(
        painter: const ArcadeCheckerPainter(drawBottomStripe: false),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 15, 16, 13),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'LEADERBOARD',
                  style: PixelText.title(size: 30, color: AppColors.parchment),
                ),
              ),
              const SizedBox(height: 14),
              _buildTypeTabs(),
              if (_selectedType == _LeaderboardType.steps) ...[
                const SizedBox(height: 10),
                FilterDropdown<String>(
                  value: _selectedPeriod,
                  options: [for (final (val, label) in _periods) (val, label)],
                  onChanged: (val) {
                    if (val != null) _selectPeriod(val);
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  double get _valueColumnWidth {
    switch (_selectedType) {
      case _LeaderboardType.steps:
        return 74;
      case _LeaderboardType.races:
        return 140;
    }
  }

  Widget _buildEmptyState() {
    // On the friends scope an empty board means "no friends to compete with"
    // rather than "no records" — nudge the user to add some.
    final bool friendsScope = _selectedScope == _LeaderboardScope.friends;
    final IconData emptyIcon = friendsScope
        ? Icons.group_add_rounded
        : _selectedType.emptyIcon;
    final String emptyTitle = friendsScope
        ? 'No friends on the board yet. Add some to compete!'
        : _selectedType.emptyTitle;
    final String? emptySubtitle = friendsScope
        ? null
        : _selectedType.emptySubtitle;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
      child: Column(
        children: [
          Icon(
            emptyIcon,
            size: 32,
            color: AppColors.textMid.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 8),
          Text(
            emptyTitle,
            style: PixelText.body(
              size: 18,
              color: AppColors.textMid,
            ).copyWith(shadows: _textShadows),
            textAlign: TextAlign.center,
          ),
          if (emptySubtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              emptySubtitle,
              style: PixelText.body(
                size: 14,
                color: AppColors.textMid,
              ).copyWith(shadows: _textShadows),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  List<_LeaderboardRow> _buildRows() {
    final rows = <_LeaderboardRow>[];
    for (final entry in _top100) {
      rows.add(
        _LeaderboardRow(
          rank: entry['rank'] as int?,
          userId: entry['userId'] as String?,
          displayName: entry['displayName'] as String? ?? 'Anonymous',
          profilePhotoUrl: entry['profilePhotoUrl'] as String?,
          valueLabel: _displayValue(entry),
          isMe: (entry['userId'] as String?) == widget.authService.userId,
          firsts: entry['firsts'] as int?,
          seconds: entry['seconds'] as int?,
          thirds: entry['thirds'] as int?,
          equippedAccessories:
              (entry['equippedAccessories'] as List?)
                  ?.whereType<Map<String, dynamic>>()
                  .toList() ??
              const [],
          animal: animalFromJson(entry['animal']),
        ),
      );
    }
    return rows;
  }

  _LeaderboardRow? _buildCurrentUserRow() {
    if (_currentUser == null || _currentUser!['inTop100'] == true) return null;
    return _LeaderboardRow(
      rank: _currentUser!['rank'] as int?,
      userId: widget.authService.userId,
      displayName: _currentUser!['displayName'] as String? ?? 'Anonymous',
      profilePhotoUrl: _currentUser!['profilePhotoUrl'] as String?,
      valueLabel: _displayValue(_currentUser!),
      isMe: true,
      firsts: _currentUser!['firsts'] as int?,
      seconds: _currentUser!['seconds'] as int?,
      thirds: _currentUser!['thirds'] as int?,
      equippedAccessories:
          (_currentUser!['equippedAccessories'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .toList() ??
          const [],
      animal: animalFromJson(_currentUser!['animal']),
    );
  }

  Widget _buildLeaderboardBoard() {
    final rows = _buildRows();
    final currentUserRow = _buildCurrentUserRow();
    final podiumRows = rows.take(3).toList();
    final listRows = rows.length > 3
        ? rows.skip(3).toList()
        : <_LeaderboardRow>[];
    final pinnedMeRow =
        currentUserRow != null &&
            !rows.any((row) => row.userId == widget.authService.userId)
        ? currentUserRow
        : null;

    return Column(
      children: [
        _buildPodiumSection(podiumRows),
        if (listRows.isNotEmpty || pinnedMeRow != null) ...[
          const SizedBox(height: 10),
          _buildRankingsList(listRows, startIndex: 3, pinnedMeRow: pinnedMeRow),
        ],
      ],
    );
  }

  Widget _buildPodiumSection(List<_LeaderboardRow> podiumRows) {
    if (podiumRows.isEmpty) return const SizedBox.shrink();

    final first = _rowWithRank(podiumRows, 1) ?? podiumRows[0];
    final second =
        _rowWithRank(podiumRows, 2) ??
        (podiumRows.length > 1 ? podiumRows[1] : null);
    final third =
        _rowWithRank(podiumRows, 3) ??
        (podiumRows.length > 2 ? podiumRows[2] : null);

    // Gold / silver / bronze pedestals on one shared "trophy slab": #1 towers
    // in the centre, every rank is colour-coded and numbered, so the top 3 read
    // as one unmistakable ranking — clearly apart from the #4+ list.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.parchmentDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.parchmentBorder, width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        child: Column(
          children: [
            _buildScopeHeader(),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(flex: 10, child: _buildPodiumTile(second, place: 2)),
                const SizedBox(width: 6),
                Expanded(
                  flex: 12,
                  child: _buildPodiumTile(first, place: 1, featured: true),
                ),
                const SizedBox(width: 6),
                Expanded(flex: 10, child: _buildPodiumTile(third, place: 3)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  _LeaderboardRow? _rowWithRank(List<_LeaderboardRow> rows, int rank) {
    for (final row in rows) {
      if (row.rank == rank) return row;
    }
    return null;
  }

  Widget _buildPodiumTile(
    _LeaderboardRow? row, {
    required int place,
    bool featured = false,
  }) {
    final double pedestalHeight;
    if (featured) {
      pedestalHeight = 80;
    } else if (place == 2) {
      pedestalHeight = 52;
    } else {
      pedestalHeight = 40;
    }
    final clusterHeight = featured ? 80.0 : 50.0;

    // Empty slot (fewer than 3 ranked): a calm, clearly-empty pedestal — never a
    // mystery winner — keeping #1 centred.
    if (row == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: clusterHeight),
          const SizedBox(height: 6),
          _PedestalBlock(place: place, height: pedestalHeight, empty: true),
        ],
      );
    }

    final avatarSize = featured ? 60.0 : 44.0;
    final nameSize = featured ? 14.5 : 12.5;
    final valueSize = featured ? 16.0 : 12.5;

    final headUnit = SizedBox(
      width: avatarSize,
      height: avatarSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: featured
                  ? [
                      BoxShadow(
                        color: AppColors.medalGold.withValues(alpha: 0.55),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: AnimatedCapybaraWithAccessories(
              accessories: row.equippedAccessories,
              size: avatarSize,
              animal: row.animal,
            ),
          ),
        ],
      ),
    );

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: clusterHeight,
          child: Align(alignment: Alignment.bottomCenter, child: headUnit),
        ),
        const SizedBox(height: 6),
        Text(
          atName(row.displayName),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: PixelText.body(
            size: nameSize,
            color: row.isMe ? AppColors.accent : AppColors.textDark,
          ),
        ),
        const SizedBox(height: 3),
        _buildPodiumValue(row, valueSize: valueSize),
        const SizedBox(height: 6),
        _PedestalBlock(place: place, height: pedestalHeight),
      ],
    );

    return _withFriendTap(row, content);
  }

  Widget _buildPodiumValue(_LeaderboardRow row, {required double valueSize}) {
    if (_selectedType == _LeaderboardType.races) {
      return FittedBox(fit: BoxFit.scaleDown, child: _buildValueContent(row));
    }

    return Text(
      row.valueLabel,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: PixelText.title(
        size: valueSize,
        color: row.isMe ? AppColors.accent : AppColors.textDark,
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildRankingsList(
    List<_LeaderboardRow> rows, {
    required int startIndex,
    _LeaderboardRow? pinnedMeRow,
  }) {
    final children = <Widget>[];
    for (int i = 0; i < rows.length; i++) {
      children.add(_buildRow(rows[i], startIndex + i));
    }
    if (pinnedMeRow != null) {
      // Visual gap signalling "out of range" jump to the user's row.
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
      children.add(_buildRow(pinnedMeRow, startIndex + rows.length));
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Column(children: children),
    );
  }

  Widget _buildRow(_LeaderboardRow row, int index) {
    final rankLabel = switch (row.rank) {
      1 => '1st',
      2 => '2nd',
      3 => '3rd',
      null => '--',
      _ => '${row.rank}',
    };

    final stripeColor = index.isOdd
        ? AppColors.parchmentDark.withValues(alpha: 0.45)
        : Colors.transparent;
    final backgroundColor = row.isMe
        ? AppColors.accent.withValues(alpha: 0.16)
        : stripeColor;

    final nameStyle = PixelText.body(
      size: 16,
      color: row.isMe ? AppColors.accent : AppColors.textDark,
    );

    final content = Container(
      key: row.isMe ? (widget.tutorialMyRowKey ?? _myRowKey) : null,
      decoration: BoxDecoration(
        color: backgroundColor,
        border: row.isMe
            ? Border(left: BorderSide(color: AppColors.accent, width: 3))
            : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: Row(
        children: [
          SizedBox(width: 42, child: _RankPill(label: rankLabel)),
          const SizedBox(width: 9),
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
                    atName(row.displayName),
                    style: nameStyle,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (row.isMe) ...[
                  const SizedBox(width: 6),
                  Text(
                    '(you)',
                    style: PixelText.pill(size: 10.5, color: AppColors.accent),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: _valueColumnWidth,
            child: Align(
              alignment: Alignment.centerRight,
              child: _buildValueContent(row),
            ),
          ),
        ],
      ),
    );

    return _withFriendTap(row, content);
  }

  Widget _withFriendTap(_LeaderboardRow row, Widget child) {
    final userId = row.userId;
    final canAddFriend = !row.isMe && userId != null && userId.isNotEmpty;
    if (!canAddFriend) return child;

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () =>
            _openFriendSheet(userId, row.displayName, row.profilePhotoUrl),
        child: child,
      ),
    );
  }

  void _openFriendSheet(
    String userId,
    String displayName,
    String? profilePhotoUrl,
  ) {
    showFriendRequestSheet(
      context: context,
      authService: widget.authService,
      backendApiService: _api,
      userId: userId,
      displayName: displayName,
      profilePhotoUrl: profilePhotoUrl,
    );
  }
}

/// Compact two-icon scope toggle (globe = global, people = friends) that sits
/// in the top-right of the podium card. Much smaller than a labelled segmented
/// control — the active scope is named by the section header beside it.
class _ScopeIconToggle extends StatelessWidget {
  const _ScopeIconToggle({required this.selected, required this.onChanged});

  final _LeaderboardScope selected;
  final ValueChanged<_LeaderboardScope> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.parchment,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.parchmentBorder, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final scope in _LeaderboardScope.values)
            _ScopeIconButton(
              icon: scope.icon,
              active: scope == selected,
              onTap: () => onChanged(scope),
            ),
        ],
      ),
    );
  }
}

class _ScopeIconButton extends StatelessWidget {
  const _ScopeIconButton({
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: active ? AppColors.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Icon(
            icon,
            size: 16,
            color: active ? AppColors.parchment : AppColors.textMid,
          ),
        ),
      ),
    );
  }
}

class _LeaderboardRow {
  final int? rank;
  final String? userId;
  final String displayName;
  final String? profilePhotoUrl;
  final String valueLabel;
  final bool isMe;
  final int? firsts;
  final int? seconds;
  final int? thirds;
  final List<Map<String, dynamic>> equippedAccessories;
  final String? animal;

  const _LeaderboardRow({
    required this.rank,
    this.userId,
    required this.displayName,
    this.profilePhotoUrl,
    required this.valueLabel,
    this.isMe = false,
    this.firsts,
    this.seconds,
    this.thirds,
    this.equippedAccessories = const [],
    this.animal,
  });
}

/// Per-rank medal palette for the podium: real gold/silver/bronze tokens with a
/// lighter top tint and a darker border so the light fills still read as solid
/// blocks, plus the worded ordinal shown on the pedestal.
class _MedalStyle {
  const _MedalStyle(this.base, this.top, this.border, this.label);

  final Color base;
  final Color top;
  final Color border;
  final String label;
}

const Map<int, _MedalStyle> _medalStyles = {
  1: _MedalStyle(
    AppColors.medalGold,
    Color(0xFFFFE875),
    Color(0xFF9F7620),
    '1ST',
  ),
  2: _MedalStyle(
    AppColors.medalSilver,
    Color(0xFFE4E4E4),
    Color(0xFF8A8A8A),
    '2ND',
  ),
  3: _MedalStyle(
    AppColors.medalBronze,
    Color(0xFFE0A05A),
    Color(0xFF8A5320),
    '3RD',
  ),
};

/// The medal-coloured pedestal under each podium avatar: a big dark numeral +
/// worded ordinal so rank is explicit even ignoring colour and position.
class _PedestalBlock extends StatelessWidget {
  const _PedestalBlock({
    required this.place,
    required this.height,
    this.empty = false,
  });

  final int place;
  final double height;
  final bool empty;

  @override
  Widget build(BuildContext context) {
    final medal = _medalStyles[place]!;
    final isFirst = place == 1;
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: empty
            ? null
            : LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [medal.top, medal.base],
              ),
        color: empty ? AppColors.parchment : null,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
        border: Border.all(
          color: empty ? AppColors.parchmentBorder : medal.border,
          width: 1.5,
        ),
      ),
      child: empty
          ? null
          : Center(
              child: Text(
                medal.label,
                style: PixelText.title(
                  size: isFirst ? 24 : 20,
                  color: AppColors.textDark,
                ),
              ),
            ),
    );
  }
}

class _RankPill extends StatelessWidget {
  const _RankPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final isPodium =
        label.endsWith('st') || label.endsWith('nd') || label.endsWith('rd');
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: PixelText.title(
        size: isPodium ? 13 : 14,
        color: isPodium ? AppColors.coinDark : AppColors.textDark,
      ),
    );
  }
}

class _PodiumSkeleton extends StatelessWidget {
  const _PodiumSkeleton();

  @override
  Widget build(BuildContext context) {
    return GameContainer(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      frameColor: AppColors.accent,
      surfaceColor: AppColors.parchment,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 128,
            height: 18,
            decoration: BoxDecoration(
              color: AppColors.parchmentBorder.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: _SkeletonPodiumTile(height: 124)),
              const SizedBox(width: 8),
              Expanded(
                child: Transform.translate(
                  offset: const Offset(0, -10),
                  child: const _SkeletonPodiumTile(height: 150),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _SkeletonPodiumTile(height: 124)),
            ],
          ),
        ],
      ),
    );
  }
}

class _SkeletonPodiumTile extends StatelessWidget {
  const _SkeletonPodiumTile({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.parchmentDark.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.parchmentBorder, width: 1),
      ),
    );
  }
}

class _RacePodiumBadges extends StatelessWidget {
  const _RacePodiumBadges({
    super.key,
    required this.firsts,
    required this.seconds,
    required this.thirds,
    required this.isMe,
  });

  final int firsts;
  final int seconds;
  final int thirds;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      alignment: WrapAlignment.end,
      children: [
        _RacePodiumBadge(
          label: '1ST',
          count: firsts,
          fill: AppColors.medalGold.withValues(alpha: 0.18),
          border: AppColors.medalGold,
          textColor: isMe ? AppColors.accent : AppColors.textDark,
        ),
        _RacePodiumBadge(
          label: '2ND',
          count: seconds,
          fill: AppColors.medalSilver.withValues(alpha: 0.2),
          border: AppColors.medalSilver.withValues(alpha: 0.9),
          textColor: isMe ? AppColors.accent : AppColors.textDark,
        ),
        _RacePodiumBadge(
          label: '3RD',
          count: thirds,
          fill: AppColors.medalBronze.withValues(alpha: 0.2),
          border: AppColors.medalBronze.withValues(alpha: 0.9),
          textColor: isMe ? AppColors.accent : AppColors.textDark,
        ),
      ],
    );
  }
}

class _RacePodiumBadge extends StatelessWidget {
  const _RacePodiumBadge({
    required this.label,
    required this.count,
    required this.fill,
    required this.border,
    required this.textColor,
  });

  final String label;
  final int count;
  final Color fill;
  final Color border;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: border, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: PixelText.title(size: 8.5, color: textColor)),
          const SizedBox(width: 4),
          Text('$count', style: PixelText.number(size: 11, color: textColor)),
        ],
      ),
    );
  }
}
