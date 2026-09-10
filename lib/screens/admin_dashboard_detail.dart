import 'package:flutter/material.dart';

import '../models/admin_metrics_dashboard.dart';
import '../styles.dart';
import '../widgets/admin_metric_widgets.dart';
import 'admin_dashboard_controller.dart';
import 'admin_onboarding_funnel.dart';
import 'admin_system_health.dart';

class AdminDashboardDetail extends StatefulWidget {
  const AdminDashboardDetail({
    super.key,
    required this.title,
    required this.controller,
  });
  final String title;
  final AdminDashboardController controller;
  @override
  State<AdminDashboardDetail> createState() => _AdminDashboardDetailState();
}

class _AdminDashboardDetailState extends State<AdminDashboardDetail> {
  int _tab = 0;
  String? _action;
  String _adSeries = 'uniqueSsvWatchers';
  AdminDashboardController get controller => widget.controller;

  List<String> get _dependencies => switch (widget.title) {
    'Growth' => ['dashboard-growth'],
    'Activity' => ['dashboard-dau-engagement'],
    'Retention' => [
      'dashboard-summary',
      'dashboard-retention-mature',
      'dashboard-retention',
    ],
    'Races & friends' => [
      'dashboard-summary',
      'dashboard-engagement',
      'dashboard-activation',
    ],
    'Invites & onboarding' => ['dashboard-funnels'],
    'Ads & shop' => _tab == 0 ? ['dashboard-revenue', 'ads'] : ['economy'],
    _ => [],
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load({bool refresh = false}) => widget.title == 'System health'
      ? controller.loadHealth()
      : controller.loadAll(_dependencies, refresh: refresh);

  AdminMetricsEnvelope? _envelope(String section) =>
      controller.state(section).envelope;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final fixedOnly =
          widget.title == 'System health' ||
          (widget.title == 'Ads & shop' && _tab == 1);
      final includeToday = [
        'Growth',
        'Activity',
        'Ads & shop',
      ].contains(widget.title);
      final data = _dependencies.map(controller.state).toList();
      final refreshing =
          data.any((entry) => entry.loading) ||
          (widget.title == 'System health' && controller.healthLoading);
      return AdminPage(
        title: widget.title,
        onRefresh: () => _load(refresh: true),
        actions: [
          IconButton(
            tooltip: 'Refresh ${widget.title}',
            onPressed: refreshing ? null : () => _load(refresh: true),
            icon: const Icon(Icons.refresh, size: 21),
          ),
        ],
        child: ListView(
          key: PageStorageKey('admin-detail-${widget.title}-$_tab'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            if (widget.title == 'Invites & onboarding' ||
                widget.title == 'Ads & shop') ...[
              _tabs(
                widget.title == 'Ads & shop'
                    ? ['Ads', 'Shop']
                    : ['Invites', 'Onboarding'],
              ),
              const SizedBox(height: 12),
            ],
            if (!fixedOnly) ...[
              AdminRangeControl(
                value: controller.range,
                includeToday: includeToday,
                onChanged: (value) {
                  controller.selectRange(value);
                  _load();
                },
              ),
              const SizedBox(height: 8),
              if (!includeToday && controller.range == AdminRange.today)
                _note(
                  'This page uses the supported 7-day cohort/window. Today-only aggregates are unavailable.',
                ),
            ],
            if (widget.title != 'System health')
              _note('Retained iOS population · coverage varies by metric'),
            for (final section in _dependencies)
              AdminDataStatus(
                data: controller.state(section),
                onRetry: () => controller.load(section, refresh: true),
              ),
            ...switch (widget.title) {
              'Growth' => _growth(),
              'Activity' => _activity(),
              'Retention' => _retention(),
              'Races & friends' => _races(),
              'Invites & onboarding' => _tab == 0 ? _invites() : _onboarding(),
              'Ads & shop' => _tab == 0 ? _ads() : _shop(),
              'System health' => [
                AdminCard(
                  child: AdminSystemHealthBody(
                    health: controller.health,
                    loading: controller.healthLoading,
                    emptyStatus: controller.healthStatus,
                    failed: controller.healthFailed,
                    stale: controller.healthFailed && controller.health != null,
                    onRefresh: controller.loadHealth,
                  ),
                ),
              ],
              _ => [],
            },
            for (final section in _dependencies)
              AdminFreshness(
                data: controller.state(section),
                label: section.replaceFirst('dashboard-', ''),
                foreground: [
                  'dashboard-growth',
                  'dashboard-retention',
                  'dashboard-dau-engagement',
                ].contains(section),
              ),
          ],
        ),
      );
    },
  );

  Widget _tabs(List<String> labels) => Row(
    children: [
      for (var i = 0; i < labels.length; i++)
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i == 0 ? 8 : 0),
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                backgroundColor: _tab == i
                    ? AppColors.of(context).successText.withValues(alpha: .12)
                    : Colors.transparent,
                foregroundColor: AppColors.of(context).textDark,
                side: BorderSide(
                  color: AppColors.of(context).textMid.withValues(alpha: .2),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () {
                if (_tab == i) return;
                setState(() => _tab = i);
                _load();
              },
              child: Text(labels[i], style: adminText(context, strong: true)),
            ),
          ),
        ),
    ],
  );

  Widget _note(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(text, style: adminText(context, size: 12, muted: true)),
  );

  Widget _group(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: adminText(context, size: 17, strong: true)),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    ),
  );

  Widget _ratio(
    String label,
    AdminRatio? ratio,
    String scope,
    String definition, {
    String? coverage,
  }) => AdminValueRow(
    label: label,
    value: adminPercent(ratio),
    subtitle:
        '${adminCount(ratio?.numerator)} of ${adminCount(ratio?.denominator)} · $scope${coverage == null ? '' : '\n$coverage'}',
    definition:
        '$definition\n\nNumerator: ${adminCount(ratio?.numerator)}. Denominator: ${adminCount(ratio?.denominator)}.\n$scope${coverage == null ? '' : '\n$coverage'}',
  );

  List<AdminPoint> _points(
    AdminMetricsEnvelope? envelope,
    AdminMetricMap? block,
    String key,
  ) => adminDailyPoints(
    block
            ?.rows('daily')
            .map((day) => AdminPoint(day.text('date') ?? '', day.integer(key)))
            .toList() ??
        [],
    envelope?.window,
    controller.range,
  );

  List<Widget> _growth() {
    final envelope = _envelope('dashboard-growth');
    return [
      AdminTrendChart(
        title: 'New signups',
        points: _points(envelope, envelope?.userGrowth, 'signups'),
        subtitle: '${controller.range.label} · ET · accounts, not installs',
      ),
      const SizedBox(height: 16),
      AdminTrendChart(
        title: 'People opening Bara',
        points: _points(
          envelope,
          envelope?.userGrowth,
          'observedForegroundUsers',
        ),
        subtitle:
            'Daily unique people · ET · ${adminCoverage(envelope?.coverage.metric('observedForegroundDau'))}',
      ),
      const SizedBox(height: 16),
      _group('Unique people over time', [
        AdminValueRow(
          label: 'Opened in 7 days',
          value: adminCount(
            envelope?.userGrowth?.integer('observedForegroundWau'),
          ),
          subtitle:
              'Trailing 7 ET days · ${adminCoverage(envelope?.coverage.metric('observedForegroundWau'))}',
          definition:
              'Distinct telemetry-capable iOS foreground users over seven ET days. Each person counts once in the period. Source: foreground telemetry.',
        ),
        const Divider(height: 1),
        AdminValueRow(
          label: 'Opened in 30 days',
          value: adminCount(
            envelope?.userGrowth?.integer('observedForegroundMau'),
          ),
          subtitle:
              'Trailing 30 ET days · ${adminCoverage(envelope?.coverage.metric('observedForegroundMau'))}',
          definition:
              'Distinct telemetry-capable iOS foreground users over thirty ET days. Daily unique users cannot be added to obtain this total. Source: foreground telemetry.',
        ),
      ]),
    ];
  }

  List<Widget> _activity() {
    final envelope = _envelope('dashboard-dau-engagement');
    final block = envelope?.dauEngagement;
    const labels = {
      'boxOpen': 'Boxes opened',
      'powerupUse': 'Powerups used',
      'dailyRewardClaim': 'Daily rewards claimed',
      'leaderboardView': 'Leaderboard viewed',
    };
    final selected = _action;
    final raw =
        block?.daily
            .map(
              (day) => AdminPoint(
                day.date ?? '',
                selected == null
                    ? day.actionBasedDau
                    : day.actionUsers[selected],
              ),
            )
            .toList() ??
        <AdminPoint>[];
    return [
      AdminMetric(
        label: 'People taking an action',
        value: block?.actionBasedDauStatus == 'gathering_data'
            ? 'Gathering data'
            : adminCount(
                block?.actionBasedDauStatus == 'available'
                    ? block?.actionBasedDauUsers
                    : null,
              ),
        scope: 'Today · ${block?.todayDate ?? 'ET date unavailable'}',
        coverage: 'Tracked iOS actions',
        definition:
            'Deduplicated users with a qualifying action today. The existing backend definition includes race participation, boxes, powerups, daily rewards, notifications, rewarded ads, leaderboard views, race creation and completion. Foregrounding alone does not qualify. Sources: durable product facts and capability-scoped telemetry.',
      ),
      const SizedBox(height: 16),
      AdminTrendChart(
        title: selected == null
            ? 'Daily active users'
            : '${labels[selected]} · people',
        points: adminDailyPoints(raw, envelope?.window, controller.range),
        subtitle:
            '${controller.range.label} · daily unique people · ET · partial telemetry coverage',
      ),
      if (selected != null)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => setState(() => _action = null),
            child: const Text('Show all active users'),
          ),
        ),
      const SizedBox(height: 16),
      _group('Feature usage today', [
        _note(
          'Select a feature to see its daily users. Events count uses; people count distinct users.',
        ),
        for (final entry in labels.entries)
          AdminValueRow(
            label: entry.value,
            value: '${adminCount(block?.actions[entry.key]?.users)} people',
            subtitle:
                '${adminCount(block?.actions[entry.key]?.events)} events · Today${entry.key == 'boxOpen'
                    ? '\n${adminCoverage(envelope?.coverage.metric('boxOpen'))}'
                    : entry.key == 'leaderboardView'
                    ? '\n${adminCoverage(envelope?.coverage.metric('leaderboardViews'))}'
                    : ''}',
            onTap: () => setState(() => _action = entry.key),
          ),
      ]),
    ];
  }

  List<Widget> _retention() {
    final envelope = _envelope('dashboard-retention');
    final block = envelope?.retention;
    final pooled = _envelope('dashboard-summary');
    final repeat = _envelope('dashboard-retention-mature')?.retention;
    return [
      _group('Do new users return?', [
        _note(
          'Exact-day returns, not “returned at any time.” Only eligible signup cohorts count.',
        ),
        for (final day in [1, 7, 30])
          _ratio(
            'Day $day return',
            pooled?.summary?.map('retention')?.ratio('d$day'),
            'Pooled mature cohorts · exact signup + $day ET days',
            'Signup-capable users with a foreground event on exactly the $day-th ET day after signup divided by eligible mature signup-capable users. Source: foreground telemetry and product database. ${adminCoverageDetail(pooled?.coverage.metric('retentionD$day'))}',
            coverage: adminCoverage(pooled?.coverage.metric('retentionD$day')),
          ),
      ]),
      _group('Do racers race again?', [
        for (final days in [7, 30])
          _ratio(
            'Another race within $days days',
            repeat?.ratio('secondRaceWithin${days}d'),
            'First finishes in last 90 days · mature $days-day follow-up',
            'Eligible first-race finishers joining a different race after completion within $days elapsed days. The cohort is based on first completion date, not signup date, and excludes forfeits, featured races and tournaments. Source: product database.',
          ),
      ]),
      _group('Eligible signup cohorts', [
        if (block?.raw('cohorts') is! List)
          _note('Unavailable')
        else if (block?.rows('cohorts').isEmpty ?? true)
          _note('Gathering data · no eligible signup cohorts')
        else
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(
              'View daily cohorts',
              style: adminText(context, strong: true),
            ),
            subtitle: Text(
              'Up to 30 dates · immature returns stay unavailable',
              style: adminText(context, size: 12, muted: true),
            ),
            children: [
              for (final row
                  in (block?.rows('cohorts') ?? <AdminMetricMap>[]).take(30))
                AdminValueRow(
                  label: row.text('signupDate') ?? 'Date unavailable',
                  value:
                      '${adminCount(row.integer('eligibleSignups'))} eligible',
                  subtitle:
                      'D1 ${adminPercent(row.ratio('d1'))} · D7 ${adminPercent(row.ratio('d7'))} · D30 ${adminPercent(row.ratio('d30'))}',
                  definition:
                      'Eligible signup-capable accounts on this ET signup date. Each horizon includes only sufficiently mature cohorts and measures exact-day foreground return. Source: foreground telemetry and product database.',
                ),
            ],
          ),
      ]),
    ];
  }

  List<Widget> _races() {
    final summary = _envelope('dashboard-summary')?.summary?.map('races');
    final envelope = _envelope('dashboard-engagement');
    final block = envelope?.raceEngagement;
    final friends = _envelope('dashboard-activation')?.activation;
    final scope =
        '${envelope?.window.days ?? (controller.range == AdminRange.month ? 30 : 7)} days · ET';
    return [
      _group('Racing now', [
        AdminValueRow(
          label: 'People in user-created races',
          value: adminCount(summary?.integer('usersInActiveNonFeaturedRaces')),
          subtitle:
              'Now · distinct accepted iOS users · excludes featured / tournaments',
          definition:
              'Distinct accepted iOS users in currently active non-featured, non-tournament races. Source: product database.',
        ),
        AdminValueRow(
          label: 'User-created races running',
          value: adminCount(summary?.integer('activeNonFeaturedRaces')),
          subtitle: 'Now · excludes featured / tournaments',
        ),
        AdminValueRow(
          label: 'Daily featured races running',
          value: adminCount(summary?.integer('activeDailyRaces')),
          subtitle: 'Now · separate race type; not a user count',
        ),
      ]),
      AdminTrendChart(
        title: 'Daily race participants',
        points: _points(envelope, block, 'liveRaceParticipants'),
        subtitle:
            '${controller.range.label} · ET · accepted users · user-created races',
      ),
      const SizedBox(height: 16),
      _group('Public & private races', [
        _note(
          'Share of races created in $scope. The server does not provide a public/private split of unique people.',
        ),
        for (final type in ['public', 'private'])
          _ratio(
            type == 'public' ? 'Public races' : 'Private races',
            block?.map('visibility')?.ratio(type),
            scope,
            'Eligible user-created, non-cancelled races created in the selected window with this visibility, divided by all eligible races created. Excludes seeded, tournament and review-created races. Source: product database.',
          ),
      ]),
      _group('Featured & ranked participation', [
        _note(
          'Separate populations in $scope; people can appear in multiple types.',
        ),
        for (final type in ['daily', 'weekly']) ...[
          AdminValueRow(
            label:
                '${type == 'daily' ? 'Daily' : 'Weekly'} featured participants',
            value: adminCount(
              block
                  ?.map('featuredParticipation')
                  ?.map(type)
                  ?.integer('activeOverlapUsers'),
            ),
            subtitle: 'Users in races overlapping this window · $scope',
            definition:
                'Distinct accepted iOS users in non-cancelled $type featured races overlapping the window. This is not a current snapshot. Source: product database.',
          ),
          AdminValueRow(
            label: '${type == 'daily' ? 'Daily' : 'Weekly'} featured joiners',
            value: adminCount(
              block
                  ?.map('featuredParticipation')
                  ?.map(type)
                  ?.integer('joinedWindowUsers'),
            ),
            subtitle: 'Distinct people joining in $scope',
          ),
        ],
        AdminValueRow(
          label: 'Ranked participants',
          value: adminCount(block?.integer('rankedParticipationUsers')),
          subtitle: 'Distinct assigned users · cohorts overlapping $scope',
        ),
      ]),
      _group('Friends per person', [
        _note(
          'Current accepted-friend distribution · retained non-review accounts',
        ),
        if (friends?.raw('friends') is! List ||
            (friends?.rows('friends').isEmpty ?? true))
          _note('Unavailable'),
        for (final row in friends?.rows('friends') ?? <AdminMetricMap>[])
          _ratio(
            '${row.text('bucket') ?? 'Unknown'} friends',
            row.ratio('ratio'),
            'Now',
            'Accounts with this many accepted friends divided by the retained, non-review account population. Source: product database.',
          ),
      ]),
    ];
  }

  List<Widget> _invites() {
    final envelope = _envelope('dashboard-funnels');
    final block = envelope?.inviteFunnel;
    final scope =
        '${envelope?.window.days ?? (controller.range == AdminRange.month ? 30 : 7)} days · ET';
    return [
      _group('Invite reach', [
        AdminValueRow(
          label: 'Referral link opens',
          value: adminCount(block?.integer('linkOpens')),
          subtitle: scope,
          definition:
              'Link-open events in the window for iOS-owned referral codes. Source: referral telemetry.',
        ),
        AdminValueRow(
          label: 'Unique link opens',
          value: adminCount(block?.integer('uniqueLinkOpens')),
          subtitle: 'Deduplicated sessions · $scope',
          definition:
              'Pseudonymously deduplicated referral link-open sessions, not necessarily unique people. Source: referral telemetry.',
        ),
        _ratio(
          'Link open → signup',
          block?.ratio('openToSignup'),
          scope,
          'Attributed signup-cohort users divided by unique link-open sessions in the window. These are separate aggregate populations, not individually matched people; this is an indicative ratio. Source: referral telemetry and product database.',
        ),
      ]),
      _group('From signup to reward', [
        _note('Attributed iOS signup cohort · $scope'),
        AdminValueRow(
          label: 'Signed up from an invite',
          value: adminCount(block?.integer('attributedSignups')),
        ),
        AdminValueRow(
          label: 'Joined a race',
          value: adminCount(block?.integer('joinedRace')),
        ),
        _ratio(
          'Signup → race',
          block?.ratio('signupToJoinedRace'),
          scope,
          'Attributed users reaching the canonical joined-race stage divided by attributed signups.',
        ),
        AdminValueRow(
          label: 'Qualified / finished',
          value: adminCount(block?.integer('qualified')),
        ),
        _ratio(
          'Race → qualified',
          block?.ratio('joinedRaceToQualified'),
          scope,
          'Attributed users reaching the canonical qualified stage divided by joined-race users.',
        ),
        AdminValueRow(
          label: 'Reward received',
          value: adminCount(block?.integer('rewarded')),
        ),
        _ratio(
          'Qualified → rewarded',
          block?.ratio('qualifiedToRewarded'),
          scope,
          'Qualified referrals with a durable reward fact divided by qualified referrals.',
        ),
      ]),
    ];
  }

  List<Widget> _onboarding() {
    final block = _envelope('dashboard-funnels')?.onboardingFunnel;
    final stages = {
      for (final row in block?.rows('stages') ?? <AdminMetricMap>[])
        row.text('key'): row,
    };
    const branches = {
      'health_escaped',
      'health_probe_inconclusive',
      'tutorial_skipped',
    };
    final maxCount = stages.values.fold<int>(
      0,
      (largest, row) => (row.integer('count') ?? 0) > largest
          ? (row.integer('count') ?? 0)
          : largest,
    );
    return [
      _group('Onboarding progress', [
        _note(
          '${block?.integer('cohortWindowDays') ?? 'Unknown'}-day start cohort · first 24 hours\nCapability-scoped iOS sessions · starts at least 24 hours old',
        ),
        _note(
          'Indented rows are branches or skips. Their percentages use all starts, never the previous step.',
        ),
        for (var i = 0; i < OnboardingFunnelSection.stageKeys.length; i++)
          Builder(
            builder: (context) {
              final key = OnboardingFunnelSection.stageKeys[i];
              final row = stages[key];
              final branch = branches.contains(key);
              final label = switch (key) {
                'health_escaped' => 'Health setup escaped',
                'health_probe_inconclusive' => 'Health check inconclusive',
                'health_cta_tapped' => 'Health connect tapped',
                _ => OnboardingFunnelSection.stageLabels[i],
              };
              return Padding(
                padding: EdgeInsets.only(left: branch ? 18 : 0, bottom: 6),
                child: Column(
                  children: [
                    AdminValueRow(
                      label: '${branch ? '↳ ' : ''}$label',
                      value: adminCount(row?.integer('count')),
                      subtitle: branch
                          ? '${adminPercent(row?.ratio('startConversion'))} of starts · side branch'
                          : '${adminPercent(row?.ratio('previousSpineConversion'))} of previous step · ${adminPercent(row?.ratio('startConversion'))} of starts',
                      definition:
                          'Distinct capability-scoped iOS onboarding sessions reaching this ${branch ? 'side exit' : 'stage'} within 24 elapsed hours of start. The cohort includes starts at least 24 hours old. Source: activation telemetry.\nStart conversion: ${adminCount(row?.ratio('startConversion').numerator)} / ${adminCount(row?.ratio('startConversion').denominator)}.${branch ? '' : '\nPrevious-spine conversion: ${adminCount(row?.ratio('previousSpineConversion').numerator)} / ${adminCount(row?.ratio('previousSpineConversion').denominator)}.'}',
                    ),
                    if (row?.integer('count') != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: maxCount == 0
                              ? 0
                              : ((row?.integer('count') ?? 0) / maxCount).clamp(
                                  0,
                                  1,
                                ),
                          minHeight: 5,
                          color: branch
                              ? AppColors.of(context).textMid
                              : AppColors.of(context).successText,
                          backgroundColor: AppColors.of(
                            context,
                          ).textMid.withValues(alpha: .1),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
      ]),
    ];
  }

  List<Widget> _ads() {
    final envelope = _envelope('dashboard-revenue');
    final block = envelope?.revenue;
    final days = block?.rows('daily') ?? <AdminMetricMap>[];
    final points = _points(envelope, block, _adSeries);
    final allowedDates = points.map((point) => point.date).toSet();
    final selectedDays = days
        .where((day) => allowedDates.contains(day.text('date')))
        .toList();
    final rewardCounts = <String, int>{};
    final invalidKinds = <String>{};
    var allKindsPresent =
        allowedDates.isNotEmpty &&
        selectedDays
            .map((day) => day.text('date'))
            .toSet()
            .containsAll(allowedDates);
    for (final day in selectedDays) {
      final rawKinds = day.raw('ssvByRewardKind');
      if (rawKinds is! List ||
          rawKinds.length != day.rows('ssvByRewardKind').length) {
        allKindsPresent = false;
      }
      for (final reward in day.rows('ssvByRewardKind')) {
        final kind = reward.text('rewardKind') ?? 'Unknown reward';
        final grants = reward.integer('grants');
        if (grants == null) invalidKinds.add(kind);
        rewardCounts[kind] = (rewardCounts[kind] ?? 0) + (grants ?? 0);
      }
    }
    final cap = controller
        .state('ads')
        .legacy
        ?.map('adRevenue')
        ?.map('capUtilization');
    return [
      _note(
        'Signed reward callbacks · retained iOS accounts. Reward type is recorded, not independently authenticated. Counts may revise after account deletion.',
      ),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final series in [
            ('uniqueSsvWatchers', 'Daily viewers'),
            ('ssvGrants', 'Ad watches'),
          ])
            ChoiceChip(
              label: Text(series.$2, style: adminText(context, size: 12)),
              selected: _adSeries == series.$1,
              showCheckmark: false,
              onSelected: (_) => setState(() => _adSeries = series.$1),
            ),
        ],
      ),
      const SizedBox(height: 8),
      AdminTrendChart(
        title: _adSeries == 'uniqueSsvWatchers'
            ? 'People watching ads'
            : 'Rewarded ad watches',
        points: points,
        subtitle:
            '${controller.range.label} · ET · ${_adSeries == 'uniqueSsvWatchers' ? 'daily unique viewers; no period total' : 'signed reward grants'}',
      ),
      const SizedBox(height: 16),
      _group('Watches by reward', [
        _note(
          '${controller.range.label} · signed grants by recorded reward type',
        ),
        if (!allKindsPresent)
          _note('Gathering data · reward-type history is incomplete'),
        if (rewardCounts.isEmpty && allKindsPresent)
          const AdminValueRow(label: 'No recorded rewarded ads', value: '0'),
        for (final entry in rewardCounts.entries)
          AdminValueRow(
            label: _rewardLabel(entry.key),
            value: invalidKinds.contains(entry.key)
                ? 'Unavailable'
                : adminCount(entry.value),
            subtitle: allKindsPresent ? null : 'Partial history only',
            definition:
                'Signed server-side reward callbacks grouped by recorded reward kind (${entry.key}). Source: rewarded-ad callbacks. These count rewarded interactions, not ad impressions or revenue. Dates use callback time in ET.',
          ),
      ]),
      _group('Coin-ad limit', [
        AdminValueRow(
          label: 'People reaching the coin-ad cap',
          value: adminCount(cap?.integer('usersAtCap')),
          subtitle:
              'Latest recorded grant day per user within 30 days\nUser-local dates · actual dates unavailable · not necessarily today',
          definition:
              'Coin-reward ad users who reached their configured cap on their latest recorded user-local grant date in the trailing 30 days. The response does not include those dates. This is neither today’s count nor a cap statistic for every ad type. Source: legacy ad grant aggregates.',
        ),
      ]),
    ];
  }

  String _rewardLabel(String key) => switch (key) {
    'coinReward' || 'coin_reward' || 'coins' => 'Coins',
    'extraSpin' || 'extra_spin' => 'Extra spin',
    'boxReroll' || 'box_reroll' => 'Box reroll',
    'racePayoutDouble' || 'race_payout_double' => 'Double race payout',
    _ => key.replaceAll('_', ' '),
  };

  List<Widget> _shop() {
    final economy = controller.state('economy').legacy?.map('coinEconomy');
    final rows = [...?economy?.rows('purchasesBySku')]
      ..sort(
        (a, b) =>
            (b.integer('count') ?? -1).compareTo(a.integer('count') ?? -1),
      );
    final rawPurchases = economy?.raw('purchasesBySku');
    final malformed =
        rawPurchases is! List || rawPurchases.length != rows.length;
    return [
      _group('Most-purchased items', [
        _note(
          'Last 30 days · ranked by purchase count\nCoin purchases in the two existing shops; not cash revenue or in-app purchases.',
        ),
        if (malformed)
          _note('Unavailable · purchase history is missing or malformed')
        else if (rows.isEmpty)
          const AdminValueRow(label: 'No purchases in this period', value: '0'),
        for (var i = 0; i < rows.length; i++)
          AdminValueRow(
            label: '${i + 1}. ${rows[i].text('sku') ?? 'Unknown item'}',
            value: '${adminCount(rows[i].integer('count'))} purchases',
            subtitle: 'Last 30 days',
            definition:
                'Coin purchases of this SKU in the trailing 30-day legacy window across the two existing coin shops. Sorted by count rather than coins spent. Source: coin purchase records.',
          ),
      ]),
    ];
  }
}
