import 'package:flutter/material.dart';

import '../../models/step_data.dart';
import '../../services/auth_service.dart';
import '../../services/backend_api_service.dart';
import '../../styles.dart';
import '../../widgets/app_avatar.dart';
import '../../widgets/coin_balance_badge.dart';
import '../../widgets/filter_dropdown.dart';
import '../../widgets/game_container.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/pill_icon_button.dart';

enum _LeaderboardType { steps, challenges, races }

_LeaderboardType _leaderboardTypeFromApi(String apiValue) {
  switch (apiValue) {
    case 'challenges':
      return _LeaderboardType.challenges;
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
      case _LeaderboardType.challenges:
        return 'challenges';
      case _LeaderboardType.races:
        return 'races';
    }
  }

  String get label {
    switch (this) {
      case _LeaderboardType.steps:
        return 'STEPS';
      case _LeaderboardType.challenges:
        return 'CHALLENGES';
      case _LeaderboardType.races:
        return 'RACES';
    }
  }

  String get trailingHeader {
    switch (this) {
      case _LeaderboardType.steps:
        return 'STEPS';
      case _LeaderboardType.challenges:
        return 'W-L';
      case _LeaderboardType.races:
        return 'PODIUMS';
    }
  }

  String get emptyTitle {
    switch (this) {
      case _LeaderboardType.steps:
        return 'No steps yet - get walking!';
      case _LeaderboardType.challenges:
        return 'No qualified challenge records yet';
      case _LeaderboardType.races:
        return 'No race records yet';
    }
  }

  String? get emptySubtitle {
    switch (this) {
      case _LeaderboardType.steps:
        return null;
      case _LeaderboardType.challenges:
        return 'Finish more matchups to unlock the record board.';
      case _LeaderboardType.races:
        return 'Complete races to start building a podium record.';
    }
  }

  IconData get emptyIcon {
    switch (this) {
      case _LeaderboardType.steps:
        return Icons.directions_walk;
      case _LeaderboardType.challenges:
        return Icons.emoji_events_rounded;
      case _LeaderboardType.races:
        return Icons.flag_rounded;
    }
  }
}

class LeaderboardTab extends StatefulWidget {
  final AuthService authService;
  final BackendApiService? backendApiService;
  final StepData? stepData;
  final int? stepGoal;
  final String? displayName;
  final String requestedType;
  final String requestedPeriod;
  final int selectionNonce;
  final VoidCallback? onOpenProfile;

  const LeaderboardTab({
    super.key,
    required this.authService,
    this.backendApiService,
    this.stepData,
    this.stepGoal,
    this.displayName,
    this.requestedType = 'steps',
    this.requestedPeriod = 'today',
    this.selectionNonce = 0,
    this.onOpenProfile,
  });

  @override
  State<LeaderboardTab> createState() => _LeaderboardTabState();
}

class _LeaderboardTabState extends State<LeaderboardTab> {
  late final BackendApiService _api;
  _LeaderboardType _selectedType = _LeaderboardType.steps;
  String _selectedPeriod = 'today';
  int _minimumCompletedChallenges = 5;
  bool _isLoading = true;
  List<Map<String, dynamic>> _top10 = [];
  Map<String, dynamic>? _currentUser;

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
    if (mounted) {
      setState(() => _isLoading = true);
    }

    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      return;
    }

    final requestType = _selectedType;
    final requestPeriod = requestType == _LeaderboardType.steps
        ? _selectedPeriod
        : 'allTime';

    try {
      final data = await _api.fetchLeaderboard(
        identityToken: token,
        type: requestType.apiValue,
        period: requestPeriod,
      );

      if (!mounted ||
          requestType != _selectedType ||
          requestPeriod !=
              (_selectedType == _LeaderboardType.steps
                  ? _selectedPeriod
                  : 'allTime')) {
        return;
      }

      setState(() {
        final top10Raw = data['top10'] as List? ?? [];
        _top10 = top10Raw.cast<Map<String, dynamic>>();
        _currentUser = data['currentUser'] as Map<String, dynamic>?;
        _minimumCompletedChallenges =
            data['minimumCompletedChallenges'] as int? ??
            _minimumCompletedChallenges;
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
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

  String _formatSteps(int steps) {
    if (steps >= 1000) {
      return '${(steps / 1000).toStringAsFixed(1)}k';
    }
    return '$steps';
  }

  String _displayValue(Map<String, dynamic> entry) {
    switch (_selectedType) {
      case _LeaderboardType.steps:
        return _formatSteps(entry['totalSteps'] as int? ?? 0);
      case _LeaderboardType.challenges:
        final wins = entry['wins'] as int? ?? 0;
        final losses = entry['losses'] as int? ?? 0;
        return '$wins-$losses';
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

    return Padding(
      padding: EdgeInsets.only(top: topInset + 12, bottom: tabBarHeight),
      child: RefreshIndicator(
        onRefresh: _loadLeaderboard,
        color: AppColors.accent,
        backgroundColor: AppColors.parchment,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(
                child: Column(
                  children: [
                    _buildTopStatusBar(),
                    const SizedBox(height: 12),
                    Text(
                      'RANKING',
                      style: PixelText.title(
                        size: 18,
                        color: AppColors.textMid,
                      ).copyWith(shadows: _textShadows),
                    ),
                    const SizedBox(height: 8),
                    _buildTypeTabs(),
                    if (_selectedType == _LeaderboardType.steps) ...[
                      const SizedBox(height: 10),
                      FilterDropdown<String>(
                        value: _selectedPeriod,
                        options: [
                          for (final (val, label) in _periods) (val, label),
                        ],
                        onChanged: (val) {
                          if (val != null) _selectPeriod(val);
                        },
                      ),
                    ],
                    if (_selectedType == _LeaderboardType.challenges) ...[
                      const SizedBox(height: 10),
                      _buildChallengeQualificationBanner(),
                    ],
                    const SizedBox(height: 16),
                    if (_isLoading)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: AppColors.accent,
                              strokeWidth: 2,
                            ),
                          ),
                        ),
                      )
                    else if (_top10.isEmpty)
                      _buildEmptyState()
                    else
                      _buildLeaderboardTable(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopStatusBar() {
    final steps = widget.stepData?.steps ?? 0;
    final goal = widget.stepGoal ?? 0;
    final stepsStr = _formatNumber(steps);
    final goalStr = goal > 0 ? _formatCompact(goal) : null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (widget.displayName != null)
                    Flexible(
                      child: Text(
                        widget.displayName!,
                        style: PixelText.title(
                          size: 26,
                          color: AppColors.textDark,
                        ).copyWith(shadows: _textShadows),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  const SizedBox(width: 8),
                  CoinBalanceBadge(
                    coins: widget.authService.coins,
                    heldCoins: widget.authService.heldCoins,
                  ),
                ],
              ),
              const SizedBox(height: 2),
              if (goalStr != null)
                Text(
                  '$stepsStr / $goalStr',
                  style: PixelText.number(
                    size: 20,
                    color: AppColors.accent,
                  ).copyWith(shadows: _textShadows),
                )
              else
                Text(
                  stepsStr,
                  style: PixelText.number(
                    size: 20,
                    color: AppColors.accent,
                  ).copyWith(shadows: _textShadows),
                ),
            ],
          ),
        ),
        ProfileAvatarButton(
          name: widget.displayName ?? 'You',
          imageUrl: widget.authService.profilePhotoUrl,
          onPressed: widget.onOpenProfile,
        ),
      ],
    );
  }

  static String _formatNumber(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  static String _formatCompact(int n) {
    if (n >= 1000) {
      return '${(n / 1000).toStringAsFixed(n % 1000 == 0 ? 0 : 1)}k';
    }
    return '$n';
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
                  ? PillButtonVariant.primary
                  : PillButtonVariant.secondary,
              fontSize: 12,
              fullWidth: true,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildChallengeQualificationBanner() {
    return Align(
      alignment: Alignment.center,
      child: Text(
        'MINIMUM $_minimumCompletedChallenges COMPLETED CHALLENGES TO QUALIFY',
        style: PixelText.body(
          size: 13,
          color: AppColors.textMid,
        ).copyWith(shadows: _textShadows),
        textAlign: TextAlign.center,
      ),
    );
  }

  double get _valueColumnWidth {
    switch (_selectedType) {
      case _LeaderboardType.steps:
        return 74;
      case _LeaderboardType.challenges:
        return 64;
      case _LeaderboardType.races:
        return 140;
    }
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(
            _selectedType.emptyIcon,
            size: 32,
            color: AppColors.textMid.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 8),
          Text(
            _selectedType.emptyTitle,
            style: PixelText.body(
              size: 18,
              color: AppColors.textMid,
            ).copyWith(shadows: _textShadows),
            textAlign: TextAlign.center,
          ),
          if (_selectedType.emptySubtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              _selectedType.emptySubtitle!,
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

  Widget _buildLeaderboardTable() {
    final rows = <_LeaderboardRow>[];
    for (final entry in _top10) {
      rows.add(
        _LeaderboardRow(
          rank: entry['rank'] as int?,
          displayName: entry['displayName'] as String? ?? 'Anonymous',
          profilePhotoUrl: entry['profilePhotoUrl'] as String?,
          valueLabel: _displayValue(entry),
          isMe: (entry['userId'] as String?) == widget.authService.userId,
          firsts: entry['firsts'] as int?,
          seconds: entry['seconds'] as int?,
          thirds: entry['thirds'] as int?,
        ),
      );
    }

    final showCurrentUser =
        _currentUser != null && _currentUser!['inTop10'] != true;

    return GameContainer(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 36,
                  child: Text(
                    '#',
                    style: PixelText.title(size: 15, color: AppColors.textMid),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'PLAYER',
                    style: PixelText.title(size: 15, color: AppColors.textMid),
                  ),
                ),
                SizedBox(
                  width: _valueColumnWidth,
                  child: Text(
                    _selectedType.trailingHeader,
                    style: PixelText.title(size: 15, color: AppColors.textMid),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 1,
            color: AppColors.parchmentBorder.withValues(alpha: 0.5),
          ),
          for (int i = 0; i < rows.length; i++) _buildRow(rows[i], i),
          if (showCurrentUser) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                '• • •',
                style: PixelText.title(size: 14, color: AppColors.textMid),
                textAlign: TextAlign.center,
              ),
            ),
            _buildRow(
              _LeaderboardRow(
                rank: _currentUser!['rank'] as int?,
                displayName:
                    _currentUser!['displayName'] as String? ?? 'Anonymous',
                profilePhotoUrl: _currentUser!['profilePhotoUrl'] as String?,
                valueLabel: _displayValue(_currentUser!),
                isMe: true,
                firsts: _currentUser!['firsts'] as int?,
                seconds: _currentUser!['seconds'] as int?,
                thirds: _currentUser!['thirds'] as int?,
              ),
              _top10.length,
            ),
          ],
        ],
      ),
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

    return Container(
      color: row.isMe
          ? AppColors.accent.withValues(alpha: 0.12)
          : index.isOdd
          ? AppColors.parchmentDark.withValues(alpha: 0.3)
          : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              rankLabel,
              style: PixelText.title(
                size:
                    rankLabel.endsWith('st') ||
                        rankLabel.endsWith('nd') ||
                        rankLabel.endsWith('rd')
                    ? 13
                    : 16,
                color: rankLabel == '--'
                    ? AppColors.textMid
                    : (rankLabel.endsWith('st') ||
                          rankLabel.endsWith('nd') ||
                          rankLabel.endsWith('rd'))
                    ? AppColors.coinMid
                    : AppColors.textDark,
              ),
              textAlign: TextAlign.center,
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
            child: Text(
              row.displayName,
              style: PixelText.body(
                size: 16,
                color: row.isMe ? AppColors.accent : AppColors.textDark,
              ),
              overflow: TextOverflow.ellipsis,
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
  }
}

class _LeaderboardRow {
  final int? rank;
  final String displayName;
  final String? profilePhotoUrl;
  final String valueLabel;
  final bool isMe;
  final int? firsts;
  final int? seconds;
  final int? thirds;

  const _LeaderboardRow({
    required this.rank,
    required this.displayName,
    this.profilePhotoUrl,
    required this.valueLabel,
    this.isMe = false,
    this.firsts,
    this.seconds,
    this.thirds,
  });
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
          Text(
            label,
            style: PixelText.title(size: 8.5, color: textColor),
          ),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: PixelText.number(size: 11, color: textColor),
          ),
        ],
      ),
    );
  }
}
