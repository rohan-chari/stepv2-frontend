import 'package:flutter/material.dart';

import '../models/loadable.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import 'loading_skeleton.dart';
import 'pill_icon_button.dart';
import 'pill_button.dart';

class StepCalendar extends StatefulWidget {
  final AuthService authService;
  final BackendApiService? backendApiService;

  const StepCalendar({
    super.key,
    required this.authService,
    this.backendApiService,
  });

  @override
  State<StepCalendar> createState() => StepCalendarState();
}

class StepCalendarState extends State<StepCalendar> {
  late final BackendApiService _api;
  late DateTime _currentMonth;
  List<Map<String, dynamic>> _days = [];
  Loadable<List<Map<String, dynamic>>> _daysState = const Loadable.initial();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _api = widget.backendApiService ?? BackendApiService();
    _currentMonth = DateTime.now();
    _loadCalendar();
  }

  Future<void> _loadCalendar() async {
    final previous = _days;
    setState(() {
      _isLoading = true;
      _daysState = previous.isEmpty
          ? const Loadable.loading()
          : Loadable.refreshing(previous);
    });

    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _daysState = Loadable.error(
            'Not signed in.',
            data: previous.isEmpty ? null : previous,
          );
        });
      }
      return;
    }

    try {
      final month =
          '${_currentMonth.year}-${_currentMonth.month.toString().padLeft(2, '0')}';
      final result = await _api.fetchStepCalendar(
        identityToken: token,
        month: month,
      );

      if (mounted) {
        setState(() {
          _days = (result['days'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          _daysState = Loadable.success(_days);
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _daysState = Loadable.error(
            'Couldn’t load calendar.',
            data: previous.isEmpty ? null : previous,
          );
        });
      }
    }
  }

  void _previousMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1);
    });
    _loadCalendar();
  }

  void _nextMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1);
    });
    _loadCalendar();
  }

  String _monthLabel() {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[_currentMonth.month - 1]} ${_currentMonth.year}';
  }

  static String _formatSteps(int steps) {
    if (steps >= 10000) return '${(steps / 1000).toStringAsFixed(0)}k';
    if (steps >= 1000) return '${(steps / 1000).toStringAsFixed(1)}k';
    return '$steps';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Month navigation
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            PillIconButton(
              icon: Icons.chevron_left,
              size: 32,
              variant: PillButtonVariant.secondary,
              onPressed: _previousMonth,
            ),
            Text(
              _monthLabel(),
              style: PixelText.title(
                size: 16,
                color: AppColors.of(context).textDark,
              ),
            ),
            PillIconButton(
              icon: Icons.chevron_right,
              size: 32,
              variant: PillButtonVariant.secondary,
              onPressed: _nextMonth,
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Day-of-week headers
        Row(
          children: ['S', 'M', 'T', 'W', 'T', 'F', 'S']
              .map(
                (d) => Expanded(
                  child: Center(
                    child: Text(
                      d,
                      style: PixelText.title(
                        size: 12,
                        color: AppColors.of(context).textMid,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 6),
        // Calendar grid
        if (_daysState.shouldShowInitialLoading ||
            (_isLoading && _days.isEmpty))
          const Padding(
            padding: EdgeInsets.all(20),
            child: LoadingSkeleton(
              child: SkeletonBox(width: double.infinity, height: 190),
            ),
          )
        else if (_daysState.isError && !_daysState.hasData)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: LoadErrorPanel(
              title: 'Couldn’t load calendar',
              message: 'Check your connection and try again.',
              onRetry: _loadCalendar,
            ),
          )
        else
          Column(
            children: [
              if (_daysState.isRefreshing)
                Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: LinearProgressIndicator(
                    minHeight: 2,
                    color: AppColors.of(context).accent,
                    backgroundColor: Colors.transparent,
                  ),
                ),
              _buildGrid(),
            ],
          ),
      ],
    );
  }

  Widget _buildGrid() {
    if (_days.isEmpty) return const SizedBox.shrink();

    // First day of month — what day of week (0 = Sunday)
    final firstDayOfWeek =
        DateTime(_currentMonth.year, _currentMonth.month, 1).weekday % 7;

    final rows = <Widget>[];
    var dayIndex = 0;

    // Build rows of 7
    while (dayIndex < _days.length) {
      final cells = <Widget>[];

      for (var col = 0; col < 7; col++) {
        // Leading empty cells for first row
        if (rows.isEmpty && col < firstDayOfWeek) {
          cells.add(const Expanded(child: SizedBox.shrink()));
          continue;
        }

        if (dayIndex >= _days.length) {
          cells.add(const Expanded(child: SizedBox.shrink()));
          continue;
        }

        final day = _days[dayIndex];
        dayIndex++;

        final steps = (day['steps'] as num?)?.toInt() ?? 0;
        final goalMet = day['goalMet'] as bool? ?? false;
        final isFuture = day['future'] as bool? ?? false;
        final isToday = day['isToday'] as bool? ?? false;
        final noData = !isToday && !isFuture && steps == 0;
        final isInactive = isFuture || noData;

        Color borderColor;
        if (isToday) {
          borderColor = AppColors.of(context).pillGold;
        } else if (isInactive) {
          borderColor = AppColors.of(
            context,
          ).parchmentBorder.withValues(alpha: 0.3);
        } else if (goalMet) {
          borderColor = AppColors.of(context).grassMid;
        } else {
          borderColor = AppColors.of(context).error;
        }

        final bgColor = isInactive
            ? AppColors.of(context).parchmentDark.withValues(alpha: 0.2)
            : AppColors.of(context).parchmentDark.withValues(alpha: 0.5);

        final textColor = isInactive
            ? AppColors.of(context).textMid.withValues(alpha: 0.3)
            : AppColors.of(context).textDark;

        cells.add(
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(2),
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: borderColor,
                  width: isToday ? 2 : 1.5,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$dayIndex',
                    style: PixelText.title(size: 12, color: textColor),
                  ),
                  if (!isInactive)
                    Text(
                      _formatSteps(steps),
                      style: PixelText.body(
                        size: 10,
                        color: goalMet
                            ? AppColors.of(context).grassMid
                            : AppColors.of(context).textMid,
                      ),
                    )
                  else
                    Text(
                      '-',
                      style: PixelText.body(
                        size: 10,
                        color: AppColors.of(
                          context,
                        ).textMid.withValues(alpha: 0.3),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      }

      rows.add(Row(children: cells));
    }

    return Column(children: rows);
  }
}
