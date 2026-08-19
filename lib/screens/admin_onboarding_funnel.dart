import 'package:flutter/material.dart';

import '../models/admin_metrics_dashboard.dart';
import '../styles.dart';

/// The activation funnel from `GET /admin/stats` → `onboardingFunnel` (§6.5).
///
/// Design notes. A funnel is not a list of numbers, it is the *shape of the
/// loss between them* — and a plain table hides exactly the thing you opened
/// the screen to find. So every stage gets a proportional bar: the eye catches
/// the notch where a bar suddenly shortens long before it reads a percentage.
/// Everything else stays deliberately flat and dense (no gradients, no motion,
/// the same PixelText idiom as the stats card above) because this is an
/// operator tool and the bars are the one expressive element it needs.
///
/// Two of the seven stages are **not** funnel stages. `health_escaped` and
/// `health_probe_inconclusive` are side exits: users leave the happy path
/// there, they do not flow through them. Chaining step-over-step retention
/// across them would produce numbers that look authoritative and mean nothing,
/// so they are drawn as muted branch rows showing their share of the top of
/// funnel, and the retention chain skips them.
///
/// Absent section → renders nothing at all. Not an error, not an empty card:
/// the backend and the app deploy independently, and an admin on a new build
/// against an old backend should simply not see a funnel yet (§8.11).
class OnboardingFunnelSection extends StatefulWidget {
  const OnboardingFunnelSection({super.key, this.funnel, this.dashboardFunnel});

  final Map<String, dynamic>? funnel;
  final AdminMetricMap? dashboardFunnel;

  /// Display order, exactly as pinned in §6.5.
  static const stageKeys = <String>[
    'onboarding_started',
    'health_cta_tapped',
    'health_granted',
    'health_escaped',
    'health_probe_inconclusive',
    'daily_intro_viewed',
    // The teaching step, which under v3 is the playable demo race. Order is
    // pinned to the backend's ONBOARDING_FUNNEL_STAGES: this list only decides
    // what is DRAWN, so the two must not drift or the rows read out of order.
    'tutorial_opened',
    'tutorial_skipped',
    'demo_box_opened',
    'demo_powerup_used',
    'demo_won',
    'tutorial_completed',
    'home_reached',
  ];

  /// Index-aligned with [stageKeys] — `stageLabels[i]` is read directly.
  static const stageLabels = <String>[
    'Started',
    'Health CTA',
    'Health granted',
    'Escaped',
    'Probe zero',
    'Race intro',
    'Tutorial opened',
    'Tutorial skipped',
    'Box opened',
    'Powerup used',
    'Race won',
    'Tutorial done',
    'Home reached',
  ];

  /// The stages users actually flow through, in order. Retention is chained
  /// along this spine only.
  ///
  /// The demo-race stages are all spine: a user genuinely flows opened → box →
  /// powerup → won → finished, so step-over-step retention is exactly the
  /// number worth reading. `tutorial_skipped` is deliberately absent from
  /// [stageKeys] as a side exit, but remains absent from this spine so it shows
  /// start-share only and never becomes a previous-stage denominator.
  static const _spine = <String>[
    'onboarding_started',
    'health_cta_tapped',
    'health_granted',
    'daily_intro_viewed',
    'tutorial_opened',
    'demo_box_opened',
    'demo_powerup_used',
    'demo_won',
    'tutorial_completed',
    'home_reached',
  ];

  static bool _isSideExit(String key) => !_spine.contains(key);

  @override
  State<OnboardingFunnelSection> createState() =>
      _OnboardingFunnelSectionState();
}

class _OnboardingFunnelSectionState extends State<OnboardingFunnelSection> {
  bool _thirtyDays = false;

  Map<String, dynamic>? _platforms(String key) {
    final raw = widget.funnel?[key];
    if (raw is! Map) return null;
    return <String, dynamic>{
      for (final entry in raw.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }

  int _count(Map<String, dynamic>? stages, String key) {
    final value = stages?[key];
    return value is num ? value.toInt() : 0;
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = widget.dashboardFunnel;
    if (dashboard != null) return _buildDashboard(context, dashboard);

    final sevenDay = _platforms('byPlatform');
    if (sevenDay == null || sevenDay.isEmpty) return const SizedBox.shrink();
    final thirtyDay = _platforms('byPlatformLast30Days');
    final active = (_thirtyDays && thirtyDay != null) ? thirtyDay : sevenDay;

    final windowDays = widget.funnel?['windowDays'];
    final sevenLabel = '${windowDays is num ? windowDays.toInt() : 7}D';

    final colors = AppColors.of(context);
    // The dashboard is product-scoped to Bara/iOS. The legacy DTO can still
    // arrive here in direct widget tests or an older response, but no Android
    // series is presented by this build.
    final platforms = <String>[
      if (active['ios'] is Map<String, dynamic>) 'ios',
    ];
    if (platforms.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Text(
                'ONBOARDING FUNNEL',
                style: PixelText.title(size: 12, color: colors.textDark),
              ),
            ),
            if (thirtyDay != null) ...[
              _WindowChip(
                label: sevenLabel,
                selected: !_thirtyDays,
                onTap: () => setState(() => _thirtyDays = false),
              ),
              const SizedBox(width: 6),
              _WindowChip(
                label: '30D',
                selected: _thirtyDays,
                onTap: () => setState(() => _thirtyDays = true),
              ),
            ],
          ],
        ),
        Text(
          'Distinct onboarding sessions reaching each stage.',
          style: PixelText.body(size: 11, color: colors.textMid),
        ),
        for (final platform in platforms) ...[
          const SizedBox(height: 10),
          Text(
            platform.toUpperCase(),
            style: PixelText.title(size: 11, color: colors.textMid),
          ),
          const SizedBox(height: 4),
          ..._stageRows(active[platform] as Map<String, dynamic>),
        ],
      ],
    );
  }

  Widget _buildDashboard(BuildContext context, AdminMetricMap funnel) {
    final colors = AppColors.of(context);
    final cohortWindowDays = funnel.integer('cohortWindowDays');
    final byKey = <String, AdminMetricMap>{};
    for (final stage in funnel.rows('stages')) {
      final key = stage.text('key');
      if (key != null && OnboardingFunnelSection.stageKeys.contains(key)) {
        byKey[key] = stage;
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'IOS',
              style: PixelText.title(size: 11, color: colors.textMid),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${cohortWindowDays?.toString() ?? 'WINDOW UNAVAILABLE'}${cohortWindowDays == null ? '' : 'D'} START COHORT · 24H',
                textAlign: TextAlign.end,
                style: PixelText.title(size: 9, color: colors.textAccent),
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        for (var i = 0; i < OnboardingFunnelSection.stageKeys.length; i++)
          _DashboardFunnelRow(
            label: OnboardingFunnelSection.stageLabels[i],
            stage: byKey[OnboardingFunnelSection.stageKeys[i]],
            sideExit: OnboardingFunnelSection._isSideExit(
              OnboardingFunnelSection.stageKeys[i],
            ),
            cohortWindowDays: cohortWindowDays,
          ),
      ],
    );
  }

  List<Widget> _stageRows(Map<String, dynamic> stages) {
    final counts = {
      for (final key in OnboardingFunnelSection.stageKeys)
        key: _count(stages, key),
    };
    // Scale to the largest stage rather than to `onboarding_started`, so the
    // bars stay meaningful even if the top of funnel is missing or somehow
    // smaller than a later stage.
    final scale = counts.values.fold<int>(0, (a, v) => v > a ? v : a);
    final start = counts['onboarding_started'] ?? 0;

    String? previousSpineKey;
    final rows = <Widget>[];
    for (var i = 0; i < OnboardingFunnelSection.stageKeys.length; i++) {
      final key = OnboardingFunnelSection.stageKeys[i];
      final count = counts[key] ?? 0;
      final sideExit = OnboardingFunnelSection._isSideExit(key);

      String trailing;
      if (sideExit) {
        trailing = start > 0
            ? '${((count / start) * 100).round()}% of start'
            : '—';
      } else if (previousSpineKey == null) {
        trailing = '—';
      } else {
        final previous = counts[previousSpineKey] ?? 0;
        trailing = previous > 0
            ? '${((count / previous) * 100).round()}%'
            : '—';
      }
      if (!sideExit) previousSpineKey = key;

      rows.add(
        _FunnelRow(
          label: OnboardingFunnelSection.stageLabels[i],
          count: count,
          trailing: trailing,
          fraction: scale > 0 ? (count / scale).clamp(0.0, 1.0) : 0.0,
          sideExit: sideExit,
        ),
      );
    }
    return rows;
  }
}

class _DashboardFunnelRow extends StatelessWidget {
  const _DashboardFunnelRow({
    required this.label,
    required this.stage,
    required this.sideExit,
    required this.cohortWindowDays,
  });

  final String label;
  final AdminMetricMap? stage;
  final bool sideExit;
  final int? cohortWindowDays;

  String _percent(AdminRatio ratio) {
    final value = ratio.percent;
    return value == null ? '—' : '${value.toStringAsFixed(1)}%';
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final count = stage?.integer('count');
    final previous = stage?.ratio('previousSpineConversion');
    final start = stage?.ratio('startConversion') ?? const AdminRatio();
    return Padding(
      padding: EdgeInsets.fromLTRB(sideExit ? 12 : 0, 4, 0, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (sideExit) ...[
            Icon(
              Icons.subdirectory_arrow_right_rounded,
              size: 13,
              color: colors.textMid,
            ),
            const SizedBox(width: 3),
          ],
          Expanded(
            child: Text(
              label,
              style: PixelText.body(size: 12, color: colors.textMid),
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              count == null
                  ? 'UNAVAILABLE'
                  : sideExit
                  ? '$count · ${_percent(start)} of start'
                  : '$count · prev ${_percent(previous ?? const AdminRatio())} · start ${_percent(start)}',
              textAlign: TextAlign.end,
              style: PixelText.title(size: 11, color: colors.textDark),
            ),
          ),
          const SizedBox(width: 2),
          Semantics(
            label: 'Definition for $label',
            button: true,
            child: InkResponse(
              radius: 18,
              onTap: () => showModalBottomSheet<void>(
                context: context,
                backgroundColor: colors.parchment,
                builder: (sheetContext) => SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label.toUpperCase(),
                          style: PixelText.title(
                            size: 14,
                            color: AppColors.of(sheetContext).textDark,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          sideExit
                              ? 'Distinct onboarding sessions taking this side exit within 24 elapsed hours of start.'
                              : 'Distinct onboarding sessions reaching this stage within 24 elapsed hours of start.',
                          style: PixelText.body(
                            size: 13,
                            color: AppColors.of(sheetContext).textMid,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'SOURCE · ACTIVATION TELEMETRY',
                          style: PixelText.title(
                            size: 10,
                            color: AppColors.of(sheetContext).textAccent,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'WINDOW · ${cohortWindowDays == null ? 'COHORT WINDOW UNAVAILABLE' : '${cohortWindowDays}D START COHORT'} · FIRST 24 ELAPSED HOURS',
                          style: PixelText.title(
                            size: 10,
                            color: AppColors.of(sheetContext).textAccent,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'COVERAGE · CAPABILITY-SCOPED IOS COHORT',
                          style: PixelText.title(
                            size: 10,
                            color: AppColors.of(sheetContext).textAccent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: colors.textMid,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WindowChip extends StatelessWidget {
  const _WindowChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? colors.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? colors.accent : colors.parchmentBorder,
              width: 1.5,
            ),
          ),
          child: Text(
            label,
            style: PixelText.title(
              size: 10,
              color: selected ? colors.textLight : colors.textMid,
            ),
          ),
        ),
      ),
    );
  }
}

/// One stage: a label/count/percentage line with its proportional bar directly
/// beneath, so the bars form a single scannable silhouette down the column.
class _FunnelRow extends StatelessWidget {
  const _FunnelRow({
    required this.label,
    required this.count,
    required this.trailing,
    required this.fraction,
    required this.sideExit,
  });

  final String label;
  final int count;
  final String trailing;
  final double fraction;
  final bool sideExit;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final barColor = sideExit ? colors.pillTerra : colors.accent;
    return Padding(
      padding: EdgeInsets.fromLTRB(sideExit ? 12 : 0, 3, 0, 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (sideExit)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(
                    Icons.subdirectory_arrow_right_rounded,
                    size: 13,
                    color: colors.textMid,
                  ),
                ),
              Expanded(
                child: Text(
                  label,
                  style: PixelText.body(size: 12, color: colors.textMid),
                ),
              ),
              Text(
                '$count',
                style: PixelText.title(size: 13, color: colors.textDark),
              ),
              SizedBox(
                width: 78,
                child: Text(
                  trailing,
                  textAlign: TextAlign.right,
                  style: PixelText.body(size: 11, color: colors.textMid),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 6,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ColoredBox(
                      color: colors.textMid.withValues(alpha: 0.14),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: fraction,
                    child: ColoredBox(color: barColor),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
