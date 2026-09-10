import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/admin_metrics_dashboard.dart';
import '../screens/admin_dashboard_controller.dart';
import '../styles.dart';

String adminCount(num? value) => value == null
    ? 'Unavailable'
    : value
          .toStringAsFixed(0)
          .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

String adminPercent(AdminRatio? ratio) => ratio?.percent == null
    ? 'Unavailable'
    : '${ratio?.percent?.toStringAsFixed(1)}%';

String adminCoverage(AdminMetricCoverage? coverage) {
  if (coverage == null) return 'Coverage unavailable';
  return switch (coverage.status) {
    AdminCoverageStatus.collecting => 'Gathering data · partial coverage',
    AdminCoverageStatus.mature => 'Tracked iOS users',
    AdminCoverageStatus.unavailable => 'Coverage unavailable',
  };
}

TextStyle adminText(
  BuildContext context, {
  double size = 14,
  bool strong = false,
  bool muted = false,
}) => TextStyle(
  fontFamily: 'sans-serif',
  fontSize: size,
  height: 1.3,
  fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
  color: muted ? AppColors.of(context).textMid : AppColors.of(context).textDark,
);

class AdminPage extends StatelessWidget {
  const AdminPage({
    super.key,
    required this.title,
    required this.child,
    this.actions,
    this.onRefresh,
  });
  final String title;
  final Widget child;
  final List<Widget>? actions;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        textTheme: theme.textTheme.apply(
          fontFamily: 'sans-serif',
          bodyColor: colors.textDark,
          displayColor: colors.textDark,
        ),
        colorScheme: theme.colorScheme.copyWith(
          primary: colors.successText,
          surface: colors.parchmentLight,
          onSurface: colors.textDark,
        ),
        dividerColor: colors.textMid.withValues(alpha: .15),
      ),
      child: Scaffold(
        backgroundColor: colors.parchmentLight,
        appBar: AppBar(
          title: Text(title, style: adminText(context, size: 22, strong: true)),
          centerTitle: false,
          backgroundColor: colors.parchmentLight,
          foregroundColor: colors.textDark,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          actions: actions,
        ),
        body: SafeArea(
          top: false,
          child: onRefresh == null
              ? child
              : RefreshIndicator(onRefresh: onRefresh!, child: child),
        ),
      ),
    );
  }
}

class AdminCard extends StatelessWidget {
  const AdminCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: colors.isDark
            ? colors.parchment
            : Color.lerp(colors.parchmentLight, Colors.white, .72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.textMid.withValues(alpha: .14)),
      ),
      child: child,
    );
  }
}

void adminDefinition(BuildContext context, String label, String description) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.of(context).parchmentLight,
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .8,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: adminText(context, size: 22, strong: true),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close definition',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Text(description, style: adminText(context, size: 16)),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class AdminMetric extends StatelessWidget {
  const AdminMetric({
    super.key,
    required this.label,
    required this.value,
    required this.scope,
    required this.definition,
    this.coverage,
    this.loading = false,
    this.onTap,
  });
  final String label, value, scope, definition;
  final String? coverage;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => AdminCard(
    padding: const EdgeInsets.fromLTRB(14, 10, 12, 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: adminText(context, size: 13, strong: true),
              ),
            ),
            IconButton(
              tooltip: 'About $label',
              onPressed: () => adminDefinition(context, label, definition),
              icon: const Icon(Icons.info_outline, size: 17),
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            ),
          ],
        ),
        InkWell(
          onTap: onTap,
          child: loading
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: LinearProgressIndicator(
                    color: AppColors.of(context).successText,
                    minHeight: 3,
                    semanticsLabel: 'Loading $label',
                  ),
                )
              : Text(
                  value,
                  style: adminText(
                    context,
                    size:
                        value == 'Unavailable' || value.startsWith('Gathering')
                        ? 16
                        : 30,
                    strong: true,
                  ),
                ),
        ),
        const SizedBox(height: 5),
        Text(scope, style: adminText(context, size: 11, muted: true)),
        if (coverage != null) ...[
          const SizedBox(height: 3),
          Text(coverage!, style: adminText(context, size: 11, muted: true)),
        ],
      ],
    ),
  );
}

class AdminRangeControl extends StatelessWidget {
  const AdminRangeControl({
    super.key,
    required this.value,
    required this.onChanged,
    this.includeToday = true,
  });
  final AdminRange value;
  final ValueChanged<AdminRange> onChanged;
  final bool includeToday;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 4,
    children: [
      for (final range in AdminRange.values)
        if (includeToday || range != AdminRange.today)
          ChoiceChip(
            label: Text(range.label),
            labelStyle: adminText(context, size: 13, strong: value == range),
            selected:
                value == range ||
                (!includeToday &&
                    value == AdminRange.today &&
                    range == AdminRange.week),
            showCheckmark: false,
            selectedColor: AppColors.of(
              context,
            ).successText.withValues(alpha: .13),
            backgroundColor: Colors.transparent,
            side: BorderSide(
              color: AppColors.of(context).textMid.withValues(alpha: .18),
            ),
            onSelected: (_) => onChanged(range),
          ),
    ],
  );
}

class AdminDataStatus extends StatelessWidget {
  const AdminDataStatus({super.key, required this.data, required this.onRetry});
  final AdminSectionData data;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    final at = data.fetchedAt;
    final stamp = at == null ? null : adminTimestamp(at);
    if (data.error == null && !data.loading) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          if (data.loading)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          Expanded(
            child: Text(
              data.loading
                  ? (stamp == null
                        ? 'Loading…'
                        : 'Updating · showing $stamp data')
                  : '${data.error}${stamp == null ? '' : ' Showing stale data from $stamp.'}',
              style: adminText(context, size: 12, muted: true),
            ),
          ),
          if (!data.loading && data.error != null)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class AdminValueRow extends StatelessWidget {
  const AdminValueRow({
    super.key,
    required this.label,
    required this.value,
    this.subtitle,
    this.definition,
    this.onTap,
  });
  final String label, value;
  final String? subtitle, definition;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap:
        onTap ??
        (definition == null
            ? null
            : () => adminDefinition(context, label, definition!)),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(label, style: adminText(context, strong: true)),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  value,
                  textAlign: TextAlign.end,
                  style: adminText(context, strong: true),
                ),
              ),
              if (onTap != null || definition != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(
                    onTap == null ? Icons.info_outline : Icons.chevron_right,
                    size: 17,
                    color: AppColors.of(context).textMid,
                  ),
                ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: adminText(context, size: 12, muted: true)),
          ],
        ],
      ),
    ),
  );
}

class AdminPoint {
  const AdminPoint(this.date, this.value);
  final String date;
  final int? value;
}

/// Dates form a complete axis; missing dates and null observations remain gaps.
List<AdminPoint> adminDailyPoints(
  List<AdminPoint> raw,
  AdminDashboardWindow? window,
  AdminRange range,
) {
  final end = DateTime.tryParse(window?.end ?? '');
  if (end == null) return const [];
  final endDate = DateTime.utc(end.year, end.month, end.day);
  final count = range == AdminRange.today
      ? 1
      : range == AdminRange.week
      ? 7
      : 30;
  final values = {for (final point in raw) point.date: point.value};
  return List.generate(count, (index) {
    final date = endDate
        .subtract(Duration(days: count - index - 1))
        .toIso8601String()
        .substring(0, 10);
    return AdminPoint(date, values[date]);
  });
}

class AdminTrendChart extends StatefulWidget {
  const AdminTrendChart({
    super.key,
    required this.title,
    required this.points,
    required this.subtitle,
  });
  final String title, subtitle;
  final List<AdminPoint> points;
  @override
  State<AdminTrendChart> createState() => _AdminTrendChartState();
}

class _AdminTrendChartState extends State<AdminTrendChart> {
  int? _selected;
  @override
  void didUpdateWidget(AdminTrendChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.title != widget.title ||
        oldWidget.points.length != widget.points.length) {
      _selected = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final points = widget.points;
    final maxValue = points.fold<int>(
      0,
      (value, point) => math.max(value, point.value ?? 0),
    );
    final index = (_selected ?? points.length - 1).clamp(
      0,
      math.max(0, points.length - 1),
    );
    final selected = points.isEmpty ? null : points[index.toInt()];
    final colors = AppColors.of(context);
    final hasData = points.any((point) => point.value != null);
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: adminText(context, size: 16, strong: true)),
          const SizedBox(height: 4),
          Text(
            widget.subtitle,
            style: adminText(context, size: 11, muted: true),
          ),
          const SizedBox(height: 12),
          if (!hasData)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Gathering data · no daily history available',
                style: adminText(context, muted: true),
              ),
            )
          else ...[
            Text(
              '${selected?.date ?? ''} · ${adminCount(selected?.value)}',
              style: adminText(context, size: 13, strong: true),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SizedBox(
                  width:
                      (maxValue.toString().length *
                                  MediaQuery.textScalerOf(context).scale(7) +
                              12)
                          .clamp(38.0, 110.0),
                  height: 94,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$maxValue',
                        style: adminText(context, size: 10, muted: true),
                      ),
                      Text(
                        '0',
                        style: adminText(context, size: 10, muted: true),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SizedBox(
                    height: 94,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (var i = 0; i < points.length; i++)
                          Expanded(
                            child: Semantics(
                              label:
                                  '${points[i].date}: ${adminCount(points[i].value)}',
                              button: true,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => setState(() => _selected = i),
                                child: Container(
                                  height: 94,
                                  alignment: Alignment.bottomCenter,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(
                                        color: colors.textMid.withValues(
                                          alpha: .3,
                                        ),
                                      ),
                                    ),
                                  ),
                                  child: points[i].value == null
                                      ? null
                                      : Container(
                                          height: points[i].value == 0
                                              ? 2
                                              : (points[i].value! /
                                                        math.max(1, maxValue) *
                                                        88)
                                                    .clamp(2, 88),
                                          decoration: BoxDecoration(
                                            color: i == index
                                                ? colors.successText
                                                : colors.successText.withValues(
                                                    alpha: .38,
                                                  ),
                                            borderRadius:
                                                const BorderRadius.vertical(
                                                  top: Radius.circular(3),
                                                ),
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  points.first.date.substring(5),
                  style: adminText(context, size: 10, muted: true),
                ),
                Text(
                  points.last.date.substring(5),
                  style: adminText(context, size: 10, muted: true),
                ),
              ],
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              dense: true,
              title: Text('Daily values', style: adminText(context, size: 12)),
              children: [
                for (final point in points)
                  AdminValueRow(
                    label: point.date,
                    value: adminCount(point.value),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Sans-serif bridge for existing operational controls. Their explicit colors
/// already come from the active app palette; small pixel sizes become readable.
class AdminSans {
  static TextStyle title({double size = 14, Color? color}) => TextStyle(
    fontFamily: 'sans-serif',
    fontSize: math.max(13, size),
    color: color,
    fontWeight: FontWeight.w600,
    height: 1.35,
  );
  static TextStyle body({double size = 14, Color? color}) => TextStyle(
    fontFamily: 'sans-serif',
    fontSize: math.max(13, size),
    color: color,
    height: 1.4,
  );
}

String adminTimestamp(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')} local';

String adminCoverageDetail(AdminMetricCoverage? coverage) =>
    '${adminCoverage(coverage)}. Eligible: ${adminCount(coverage?.eligible)} of ${adminCount(coverage?.totalPopulation)} (${coverage?.eligibilityPercent?.toStringAsFixed(1) ?? 'unavailable'}%). Collecting since: ${coverage?.collectingSince ?? 'unavailable'}.';

class AdminFreshness extends StatelessWidget {
  const AdminFreshness({
    super.key,
    required this.data,
    required this.label,
    this.foreground = false,
  });
  final AdminSectionData data;
  final String label;
  final bool foreground;
  @override
  Widget build(BuildContext context) {
    final at = data.fetchedAt;
    if (at == null) return const SizedBox.shrink();
    final envelope = data.envelope;
    final sources = <String>[];
    final warnings = <String>[];
    if (envelope != null) {
      for (final source in [
        ('Product data', envelope.sources.productDb),
        if (foreground)
          ('App-open telemetry', envelope.sources.foregroundActivity),
      ]) {
        final status = switch (source.$2.status) {
          AdminSourceStatus.available => 'available',
          AdminSourceStatus.collecting => 'gathering data',
          AdminSourceStatus.stale => 'STALE',
          AdminSourceStatus.error => 'source error',
          AdminSourceStatus.disabled => 'disabled',
          AdminSourceStatus.notConfigured => 'not configured',
          AdminSourceStatus.unavailable => 'unavailable',
        };
        sources.add(
          '${source.$1}: $status · as of ${source.$2.asOf ?? 'unavailable'}',
        );
        if (source.$2.status != AdminSourceStatus.available) {
          warnings.add('${source.$1}: $status');
        }
      }
    }
    final name = switch (label) {
      'summary' => 'Overview',
      'growth' => 'Growth',
      'dau-engagement' => 'Activity',
      'retention' => 'Signup cohorts',
      'retention-mature' => 'Repeat racers',
      'engagement' => 'Races',
      'activation' => 'Friends',
      'funnels' => 'Funnels',
      'revenue' => 'Ad viewers',
      'ads' => 'Ad limits',
      'economy' => 'Shop',
      _ => label,
    };
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 8),
      child: InkWell(
        onTap: () => adminDefinition(
          context,
          '$name data freshness',
          'Fetched ${adminTimestamp(at)}${data.error == null ? '' : ' · STALE'}.\n\n${sources.isEmpty ? 'Source timestamps are not supplied for this legacy aggregate.' : sources.join('\n')}',
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                '$name · ${adminTimestamp(at)}${data.error == null ? '' : ' · STALE'}${warnings.isEmpty ? '' : '\n${warnings.join(' · ')}'}',
                style: adminText(context, size: 11, muted: true),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.info_outline,
              size: 16,
              color: AppColors.of(context).textMid,
            ),
          ],
        ),
      ),
    );
  }
}
