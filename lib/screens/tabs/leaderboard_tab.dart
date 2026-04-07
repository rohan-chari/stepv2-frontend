import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/backend_api_service.dart';
import '../../styles.dart';
import '../../models/step_data.dart';
import '../../widgets/filter_dropdown.dart';
import '../../widgets/game_container.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/pill_icon_button.dart';
import '../../widgets/spinning_coin.dart';

class LeaderboardTab extends StatefulWidget {
  final AuthService authService;
  final BackendApiService? backendApiService;
  final StepData? stepData;
  final int? stepGoal;
  final String? displayName;
  final VoidCallback? onOpenProfile;

  const LeaderboardTab({
    super.key,
    required this.authService,
    this.backendApiService,
    this.stepData,
    this.stepGoal,
    this.displayName,
    this.onOpenProfile,
  });

  @override
  State<LeaderboardTab> createState() => _LeaderboardTabState();
}

class _LeaderboardTabState extends State<LeaderboardTab> {
  late final BackendApiService _api;
  String _selectedPeriod = 'today';
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
    _loadLeaderboard();
  }

  Future<void> _loadLeaderboard() async {
    if (mounted) setState(() => _isLoading = true);

    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final data = await _api.fetchLeaderboard(
        identityToken: token,
        period: _selectedPeriod,
      );

      if (mounted) {
        setState(() {
          final top10Raw = data['top10'] as List? ?? [];
          _top10 = top10Raw.cast<Map<String, dynamic>>();
          _currentUser = data['currentUser'] as Map<String, dynamic>?;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _selectPeriod(String period) {
    if (period == _selectedPeriod) return;
    setState(() => _selectedPeriod = period);
    _loadLeaderboard();
  }

  String _formatSteps(int steps) {
    if (steps >= 1000) {
      return '${(steps / 1000).toStringAsFixed(1)}k';
    }
    return '$steps';
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
                    const SizedBox(height: 6),
                    FilterDropdown<String>(
                      value: _selectedPeriod,
                      options: [
                        for (final (val, label) in _periods) (val, label),
                      ],
                      onChanged: (val) {
                        if (val != null) _selectPeriod(val);
                      },
                    ),
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
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Column(
                          children: [
                            Icon(
                              Icons.directions_walk,
                              size: 32,
                              color: AppColors.textMid.withValues(alpha: 0.6),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'No steps yet \u2014 get walking!',
                              style: PixelText.body(
                                size: 18,
                                color: AppColors.textMid,
                              ).copyWith(shadows: _textShadows),
                            ),
                          ],
                        ),
                      )
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
                  const SpinningCoin(size: 18),
                  const SizedBox(width: 3),
                  Text(
                    '${widget.authService.coins}',
                    style: PixelText.number(
                      size: 16,
                      color: AppColors.coinDark,
                    ).copyWith(shadows: _textShadows),
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
        PillIconButton(
          icon: Icons.person_rounded,
          size: 36,
          variant: PillButtonVariant.secondary,
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
    if (n >= 1000)
      return '${(n / 1000).toStringAsFixed(n % 1000 == 0 ? 0 : 1)}k';
    return '$n';
  }

  Widget _buildLeaderboardTable() {
    final rows = <_LeaderboardRow>[];
    for (final entry in _top10) {
      rows.add(
        _LeaderboardRow(
          rank: entry['rank'] as int? ?? 0,
          displayName: entry['displayName'] as String? ?? 'Anonymous',
          totalSteps: entry['totalSteps'] as int? ?? 0,
          isMe: (entry['userId'] as String?) == widget.authService.userId,
        ),
      );
    }

    final showCurrentUser =
        _currentUser != null && _currentUser!['inTop10'] != true;

    return GameContainer(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
      child: Column(
        children: [
          // Header
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
                Text(
                  'STEPS',
                  style: PixelText.title(size: 15, color: AppColors.textMid),
                ),
              ],
            ),
          ),
          Container(
            height: 1,
            color: AppColors.parchmentBorder.withValues(alpha: 0.5),
          ),
          // Rows
          for (int i = 0; i < rows.length; i++) _buildRow(rows[i], i),
          // Ellipsis + current user
          if (showCurrentUser) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                '\u2022 \u2022 \u2022',
                style: PixelText.title(size: 14, color: AppColors.textMid),
                textAlign: TextAlign.center,
              ),
            ),
            _buildRow(
              _LeaderboardRow(
                rank: _currentUser!['rank'] as int? ?? 0,
                displayName:
                    _currentUser!['displayName'] as String? ?? 'Anonymous',
                totalSteps: _currentUser!['totalSteps'] as int? ?? 0,
                isMe: true,
              ),
              _top10.length,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRow(_LeaderboardRow row, int index) {
    final rankLabel = row.rank == 1
        ? '1st'
        : row.rank == 2
        ? '2nd'
        : row.rank == 3
        ? '3rd'
        : null;

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
            child: rankLabel != null
                ? Text(
                    rankLabel,
                    style: PixelText.title(size: 13, color: AppColors.coinMid),
                    textAlign: TextAlign.center,
                  )
                : Text(
                    '${row.rank}',
                    style: PixelText.title(size: 16, color: AppColors.textDark),
                    textAlign: TextAlign.center,
                  ),
          ),
          const SizedBox(width: 8),
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
          Text(
            _formatSteps(row.totalSteps),
            style: PixelText.title(
              size: 16,
              color: row.isMe ? AppColors.accent : AppColors.textDark,
            ),
          ),
        ],
      ),
    );
  }
}

class _LeaderboardRow {
  final int rank;
  final String displayName;
  final int totalSteps;
  final bool isMe;

  const _LeaderboardRow({
    required this.rank,
    required this.displayName,
    required this.totalSteps,
    this.isMe = false,
  });
}
