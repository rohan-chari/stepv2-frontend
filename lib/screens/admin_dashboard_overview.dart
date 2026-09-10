import 'package:flutter/material.dart';

import '../styles.dart';
import '../widgets/admin_metric_widgets.dart';
import 'admin_dashboard_controller.dart';

const adminOverviewSections = [
  'dashboard-summary',
  'dashboard-growth',
  'dashboard-dau-engagement',
];

class AdminDashboardOverview extends StatefulWidget {
  const AdminDashboardOverview({
    super.key,
    required this.controller,
    required this.onOpen,
  });
  final AdminDashboardController controller;
  final ValueChanged<String> onOpen;
  @override
  State<AdminDashboardOverview> createState() => _AdminDashboardOverviewState();
}

class _AdminDashboardOverviewState extends State<AdminDashboardOverview> {
  String _series = 'Signups';

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final summaryData = controller.state('dashboard-summary');
    final growthData = controller.state('dashboard-growth');
    final actionData = controller.state('dashboard-dau-engagement');
    final summary = summaryData.envelope;
    final growth = growthData.envelope;
    final actions = actionData.envelope;
    final growthSummary = summary?.summary?.map('growth');
    final range = controller.range;
    final signupPoints = adminDailyPoints(
      growth?.userGrowth
              ?.rows('daily')
              .map(
                (row) =>
                    AdminPoint(row.text('date') ?? '', row.integer('signups')),
              )
              .toList() ??
          [],
      growth?.window,
      range,
    );
    final int? signups = switch (range) {
      AdminRange.today => growthSummary?.integer('signupsToday'),
      AdminRange.week => growthSummary?.integer('signupsLast7Days'),
      AdminRange.month =>
        signupPoints.isNotEmpty &&
                signupPoints.every((point) => point.value != null)
            ? signupPoints.fold<int>(
                0,
                (total, point) => total + (point.value ?? 0),
              )
            : null,
    };
    final coverageKey = switch (range) {
      AdminRange.today => 'observedForegroundDau',
      AdminRange.week => 'observedForegroundWau',
      AdminRange.month => 'observedForegroundMau',
    };
    final appOpenEnvelope = range == AdminRange.today ? summary : growth;
    final opens = range == AdminRange.today
        ? growthSummary?.integer(coverageKey)
        : growth?.userGrowth?.integer(coverageKey);
    final points = switch (_series) {
      'App opens' => adminDailyPoints(
        growth?.userGrowth
                ?.rows('daily')
                .map(
                  (row) => AdminPoint(
                    row.text('date') ?? '',
                    row.integer('observedForegroundUsers'),
                  ),
                )
                .toList() ??
            [],
        growth?.window,
        range,
      ),
      'Active users' => adminDailyPoints(
        actions?.dauEngagement?.daily
                .map((row) => AdminPoint(row.date ?? '', row.actionBasedDau))
                .toList() ??
            [],
        actions?.window,
        range,
      ),
      _ => signupPoints,
    };
    final raceCount = summary?.summary
        ?.map('races')
        ?.integer('usersInActiveNonFeaturedRaces');
    final metricCards = [
      AdminMetric(
        label: 'New signups',
        value: adminCount(signups),
        scope: '${range.label} · ET',
        definition:
            'New retained, non-review iOS accounts created during this period. Today and seven days use the server’s summary; 30 days uses complete daily signup buckets. Accounts are not installs. Source: product database.',
        loading: range == AdminRange.month
            ? growthData.loading && growth == null
            : summaryData.loading && summary == null,
        onTap: () => widget.onOpen('Growth'),
      ),
      AdminMetric(
        label: 'App opens',
        value: adminCount(opens),
        scope: '${range.label} · people, not sessions',
        coverage: adminCoverage(appOpenEnvelope?.coverage.metric(coverageKey)),
        definition:
            'Distinct telemetry-capable iOS users observed opening/foregrounding Bara in ${range.label.toLowerCase()}. This is the server’s ${range == AdminRange.today
                ? 'DAU'
                : range == AdminRange.week
                ? 'WAU'
                : 'MAU'}, never a sum of daily users. Older clients without foreground telemetry are missing. Source: foreground telemetry. ${adminCoverageDetail(appOpenEnvelope?.coverage.metric(coverageKey))}',
        loading: range == AdminRange.today
            ? summaryData.loading && summary == null
            : growthData.loading && growth == null,
        onTap: () => widget.onOpen('Growth'),
      ),
      AdminMetric(
        label: 'Active users',
        value: actions?.dauEngagement?.actionBasedDauStatus == 'gathering_data'
            ? 'Gathering data'
            : adminCount(
                actions?.dauEngagement?.actionBasedDauStatus == 'available'
                    ? actions?.dauEngagement?.actionBasedDauUsers
                    : null,
              ),
        scope:
            'Today · ${actions?.dauEngagement?.todayDate ?? 'ET date unavailable'}',
        coverage: 'Tracked iOS actions',
        definition:
            'Distinct iOS users with a qualifying action today, deduplicated by the backend. Includes races, box opens, powerups, daily rewards, notification opens, rewarded ads, leaderboard views, race creation and completion. Coverage depends on each action source; an app open alone does not qualify. The range selector changes the daily chart, not this Today snapshot.',
        loading: actionData.loading && actions == null,
        onTap: () => widget.onOpen('Activity'),
      ),
      AdminMetric(
        label: 'People racing',
        value: adminCount(raceCount),
        scope: 'Now · user-created races',
        coverage: 'iOS · excludes featured / tournaments',
        definition:
            'Distinct accepted iOS users in active non-featured, non-tournament races now. Other race types are listed separately on Races & friends. A current snapshot; changing date range does not change its definition. Source: product database.',
        loading: summaryData.loading && summary == null,
        onTap: () => widget.onOpen('Races & friends'),
      ),
    ];
    return ListView(
      key: const PageStorageKey('admin-overview-scroll'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${adminCount(growthSummary?.integer('totalSignups'))} total accounts',
                style: adminText(context, size: 14, strong: true),
              ),
            ),
            IconButton(
              tooltip: 'About total accounts',
              onPressed: () => adminDefinition(
                context,
                'Total accounts',
                'Current retained, non-review iOS accounts using Apple or Google sign-in. Deleted accounts are excluded. This measures accounts, not installs. Source: product database.',
              ),
              icon: const Icon(Icons.info_outline, size: 17),
            ),
          ],
        ),
        Text(
          'Retained iOS accounts · activity coverage varies',
          style: adminText(context, size: 11, muted: true),
        ),
        const SizedBox(height: 10),
        AdminRangeControl(
          value: range,
          onChanged: (value) {
            controller.selectRange(value);
            controller.loadAll(adminOverviewSections);
          },
        ),
        if (summaryData.fetchedAt != null)
          Text(
            'Snapshot fetched ${adminTimestamp(summaryData.fetchedAt!)}',
            style: adminText(context, size: 10, muted: true),
          ),
        const SizedBox(height: 12),
        for (final section in adminOverviewSections)
          AdminDataStatus(
            data: controller.state(section),
            onRetry: () => controller.load(section, refresh: true),
          ),
        LayoutBuilder(
          builder: (context, constraints) {
            final singleColumn =
                constraints.maxWidth < 300 ||
                MediaQuery.textScalerOf(context).scale(14) > 21;
            final width = singleColumn
                ? constraints.maxWidth
                : (constraints.maxWidth - 10) / 2;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final card in metricCards)
                  SizedBox(width: width, child: card),
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final series in ['Signups', 'App opens', 'Active users'])
              ChoiceChip(
                label: Text(series, style: adminText(context, size: 12)),
                selected: _series == series,
                showCheckmark: false,
                selectedColor: AppColors.of(
                  context,
                ).successText.withValues(alpha: .13),
                onSelected: (_) => setState(() => _series = series),
              ),
          ],
        ),
        const SizedBox(height: 8),
        AdminTrendChart(
          title: '$_series trend',
          points: points,
          subtitle:
              '${range.label} · daily counts · ET${_series == 'App opens' ? ' · ${adminCoverage(growth?.coverage.metric('observedForegroundDau'))}' : ' · tracked iOS'}',
        ),
        for (final section in adminOverviewSections)
          AdminFreshness(
            data: controller.state(section),
            label: section.replaceFirst('dashboard-', ''),
            foreground: section != 'dashboard-summary',
          ),
        const SizedBox(height: 22),
        Text('Explore', style: adminText(context, size: 18, strong: true)),
        const SizedBox(height: 6),
        for (final route in const [
          ('Growth', 'Signups & people opening Bara', Icons.trending_up),
          (
            'Activity',
            'Daily actions & feature usage',
            Icons.touch_app_outlined,
          ),
          ('Retention', 'Returning users & repeat racers', Icons.replay),
          (
            'Races & friends',
            'Participation & connections',
            Icons.people_outline,
          ),
          (
            'Invites & onboarding',
            'Referrals & onboarding progress',
            Icons.route_outlined,
          ),
          (
            'Ads & shop',
            'Rewarded ads & popular purchases',
            Icons.storefront_outlined,
          ),
          (
            'System health',
            'Server status & request failures',
            Icons.monitor_heart_outlined,
          ),
        ]) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(route.$3, color: AppColors.of(context).successText),
            title: Text(
              route.$1,
              style: adminText(context, size: 15, strong: true),
            ),
            subtitle: Text(
              route.$2,
              style: adminText(context, size: 12, muted: true),
            ),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: () => widget.onOpen(route.$1),
          ),
          const Divider(height: 1),
        ],
      ],
    );
  }
}
