import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/backend_api_service.dart';
import '../../styles.dart';
import '../../widgets/filter_dropdown.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/tab_layout.dart';

class LeaderboardTab extends StatefulWidget {
  final AuthService authService;
  final BackendApiService? backendApiService;

  const LeaderboardTab({
    super.key,
    required this.authService,
    this.backendApiService,
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

  Widget _buildPeriodSelector() {
    return FilterDropdown<String>(
      value: _selectedPeriod,
      options: [for (final (val, label) in _periods) (val, label)],
      onChanged: (val) {
        if (val != null) _selectPeriod(val);
      },
    );
  }

  Widget _buildTable(
    List<TableRow> rows, {
    bool showEllipsis = false,
    List<TableRow>? trailingRows,
  }) {
    final allRows = [...rows];

    if (showEllipsis) {
      allRows.add(
        TableRow(
          children: [
            const SizedBox.shrink(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Center(
                child: Text(
                  '\u2022 \u2022 \u2022',
                  style: PixelText.title(size: 18, color: AppColors.textMid),
                ),
              ),
            ),
            const SizedBox.shrink(),
          ],
        ),
      );
    }

    allRows.addAll(trailingRows ?? []);

    return Table(
      columnWidths: const {
        0: FixedColumnWidth(32),
        1: FlexColumnWidth(),
        2: IntrinsicColumnWidth(),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      border: TableBorder(
        horizontalInside: BorderSide(
          color: AppColors.parchmentBorder.withValues(alpha: 0.4),
          width: 0.5,
        ),
      ),
      children: allRows,
    );
  }

  TableRow _buildTableRow({
    required int rank,
    required String displayName,
    required int totalSteps,
    bool isCurrentUser = false,
    bool isTop3 = false,
  }) {
    final alternateRow = rank.isEven;
    return TableRow(
      decoration: BoxDecoration(
        color: alternateRow
            ? AppColors.accent.withValues(alpha: 0.07)
            : Colors.transparent,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Text(
            '$rank',
            style: PixelText.title(size: 18, color: AppColors.textDark),
            textAlign: TextAlign.right,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          child: Text(
            displayName,
            style: PixelText.body(size: 18, color: AppColors.textDark),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Text(
            _formatSteps(totalSteps),
            style: PixelText.title(size: 18, color: AppColors.textDark),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return TabLayout(
      title: 'LEADERBOARD',
      onRefresh: _loadLeaderboard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPeriodSelector(),
          const SizedBox(height: 12),
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
          else ...[
            if (_top10.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.directions_walk, size: 32, color: AppColors.textMid),
                      const SizedBox(height: 8),
                      Text(
                        'No steps yet \u2014 get walking!',
                        style: PixelText.body(size: 18, color: AppColors.textMid),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              _buildTable(
                _top10.map((entry) {
                  final rank = entry['rank'] as int;
                  final userId = entry['userId'] as String;
                  return _buildTableRow(
                    rank: rank,
                    displayName:
                        entry['displayName'] as String? ?? 'Anonymous',
                    totalSteps: entry['totalSteps'] as int? ?? 0,
                    isCurrentUser: userId == widget.authService.userId,
                    isTop3: rank <= 3,
                  );
                }).toList(),
                showEllipsis: _currentUser != null &&
                    _currentUser!['inTop10'] != true,
                trailingRows: _currentUser != null &&
                        _currentUser!['inTop10'] != true
                    ? [
                        _buildTableRow(
                          rank: _currentUser!['rank'] as int? ?? 0,
                          displayName:
                              _currentUser!['displayName'] as String? ??
                                  'Anonymous',
                          totalSteps:
                              _currentUser!['totalSteps'] as int? ?? 0,
                          isCurrentUser: true,
                        ),
                      ]
                    : null,
              ),
            ],
          ],
        ],
      ),
    );
  }
}
