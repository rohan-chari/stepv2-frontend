import 'package:flutter/material.dart';

import '../models/admin_metrics_dashboard.dart';
import '../styles.dart';
import 'admin_onboarding_funnel.dart';

const _unavailable = 'UNAVAILABLE';

String _number(int? value) {
  if (value == null) return _unavailable;
  final digits = value.abs().toString();
  final output = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) output.write(',');
    output.write(digits[i]);
  }
  return output.toString();
}

String _decimal(double? value) =>
    value == null ? _unavailable : value.toStringAsFixed(1);

String _ratio(AdminRatio ratio) {
  if (ratio.numerator == null || ratio.denominator == null) {
    return _unavailable;
  }
  final percentage = ratio.percent;
  final percent = percentage == null
      ? '—'
      : '${percentage.toStringAsFixed(1)}%';
  return '${_number(ratio.numerator)} / ${_number(ratio.denominator)} · $percent';
}

String _average(AdminAverage average) {
  if (average.numerator == null || average.denominator == null) {
    return _unavailable;
  }
  return '${_number(average.numerator)} / ${_number(average.denominator)} · '
      '${_decimal(average.average)} avg';
}

String _coverageDescription(AdminMetricCoverage? coverage) {
  final collectingSince = coverage?.collectingSince;
  final eligibilityPercent = coverage?.eligibilityPercent;
  return switch (coverage?.status) {
    AdminCoverageStatus.collecting =>
      collectingSince == null
          ? 'COLLECTING'
          : 'COLLECTING SINCE $collectingSince',
    AdminCoverageStatus.mature =>
      eligibilityPercent == null
          ? 'MATURE'
          : '${eligibilityPercent.toStringAsFixed(1)}% ELIGIBLE',
    AdminCoverageStatus.unavailable || null => 'UNAVAILABLE',
  };
}

String _retentionCoverage(AdminMetricsEnvelope envelope) =>
    'D1 ${_coverageDescription(envelope.coverage.metric('retentionD1'))} · '
    'D7 ${_coverageDescription(envelope.coverage.metric('retentionD7'))} · '
    'D30 ${_coverageDescription(envelope.coverage.metric('retentionD30'))}';

class AdminMetricsStatePanel extends StatelessWidget {
  const AdminMetricsStatePanel({
    super.key,
    required this.message,
    this.onRetry,
    this.retryKey,
  });

  final String message;
  final VoidCallback? onRetry;
  final Key? retryKey;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: PixelText.body(size: 12, color: colors.textMid)),
          if (onRetry != null) ...[
            const SizedBox(height: 6),
            TextButton(
              key: retryKey,
              onPressed: onRetry,
              child: Text(
                'RETRY',
                style: PixelText.title(size: 12, color: colors.textAccent),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class AdminMetricsSectionBody extends StatelessWidget {
  const AdminMetricsSectionBody({
    super.key,
    required this.section,
    required this.envelope,
  });

  final String section;
  final AdminMetricsEnvelope envelope;

  @override
  Widget build(BuildContext context) {
    final body = switch (section) {
      'dashboard-summary' => _summary(context, envelope.summary),
      'dashboard-growth' => _growth(context, envelope.userGrowth),
      'dashboard-funnels-invite' => _invite(context, envelope.inviteFunnel),
      'dashboard-funnels-onboarding' => _onboarding(
        context,
        envelope.onboardingFunnel,
      ),
      'dashboard-activation' => _activation(context, envelope.activation),
      'dashboard-retention' => _retention(context, envelope.retention),
      'dashboard-engagement' => _engagement(context, envelope.raceEngagement),
      'dashboard-virality' => _virality(context, envelope.virality),
      'dashboard-revenue' => _revenue(context, envelope.revenue),
      'dashboard-release-adoption' => _release(
        context,
        envelope.releaseAdoption,
      ),
      _ => const AdminMetricsStatePanel(message: 'Section unavailable.'),
    };
    return _MetricProvenanceScope(
      envelope: envelope,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MetadataStrip(envelope: envelope),
          const SizedBox(height: 8),
          body,
        ],
      ),
    );
  }

  Widget _summary(BuildContext context, AdminMetricMap? block) {
    if (block == null) {
      return const AdminMetricsStatePanel(message: _unavailable);
    }
    final growth = block.map('growth');
    final retention = block.map('retention');
    final races = block.map('races');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _MetricHeading('GROWTH'),
        _MetricRow(
          label: 'Total accounts',
          value: _number(growth?.integer('totalSignups')),
          definition:
              'Retained non-review iOS accounts, whether signed in with Apple or Google; this is not installs.',
          window: 'CURRENT RETAINED-ACCOUNT SNAPSHOT',
        ),
        _MetricRow(
          label: 'Signups today',
          value: _number(growth?.integer('signupsToday')),
          definition: 'Accounts created in the current America/New_York day.',
          window: 'TODAY · ET',
        ),
        _MetricRow(
          label: 'Signups last 7 days',
          value: _number(growth?.integer('signupsLast7Days')),
          definition: 'Trailing seven ET calendar days, including today.',
          window: 'TRAILING 7D · ET',
        ),
        _MetricRow(
          label: 'Engaged box openers today',
          value: _number(growth?.integer('engagedBoxOpenersToday')),
          definition:
              'Distinct users with a durable mystery-box-open event today.',
          coverage: envelope.coverage.metric('boxOpen'),
          window: 'TODAY · ET',
        ),
        _MetricRow(
          label: 'Observed foreground DAU',
          value: _number(growth?.integer('observedForegroundDau')),
          definition:
              'Capable iOS users observed foregrounded today; not whole-population DAU.',
          coverage: envelope.coverage.metric('observedForegroundDau'),
          source: 'FOREGROUND TELEMETRY',
          window: 'TODAY · ET',
        ),
        _MetricRow(
          label: 'Observed foreground WAU',
          value: _number(growth?.integer('observedForegroundWau')),
          definition:
              'Capable iOS users observed over the trailing seven ET days.',
          coverage: envelope.coverage.metric('observedForegroundWau'),
          source: 'FOREGROUND TELEMETRY',
          window: 'TRAILING 7D · ET',
        ),
        const _MetricHeading('RETENTION'),
        _MetricRow(
          label: 'Observed D1',
          value: _ratio(retention?.ratio('d1') ?? const AdminRatio()),
          definition:
              'Signup-capable cohort returning on exact signup + 1 ET day.',
          coverage: envelope.coverage.metric('retentionD1'),
          source: 'FOREGROUND TELEMETRY + PRODUCT DB',
          window: 'SIGNUP COHORT · EXACT +1 ET DAY',
        ),
        _MetricRow(
          label: 'Observed D7',
          value: _ratio(retention?.ratio('d7') ?? const AdminRatio()),
          definition:
              'Signup-capable cohort returning on exact signup + 7 ET days.',
          coverage: envelope.coverage.metric('retentionD7'),
          source: 'FOREGROUND TELEMETRY + PRODUCT DB',
          window: 'SIGNUP COHORT · EXACT +7 ET DAY',
        ),
        _MetricRow(
          label: 'Observed D30',
          value: _ratio(retention?.ratio('d30') ?? const AdminRatio()),
          definition:
              'Signup-capable cohort returning on exact signup + 30 ET days.',
          coverage: envelope.coverage.metric('retentionD30'),
          source: 'FOREGROUND TELEMETRY + PRODUCT DB',
          window: 'SIGNUP COHORT · EXACT +30 ET DAY',
        ),
        const _MetricHeading('RACES'),
        _MetricRow(
          label: 'Users in active non-featured races',
          value: _number(races?.integer('usersInActiveNonFeaturedRaces')),
          definition:
              'Distinct accepted iOS users in active user-created races now.',
          window: 'CURRENT SNAPSHOT',
        ),
        _MetricRow(
          label: 'Active non-featured races',
          value: _number(races?.integer('activeNonFeaturedRaces')),
          definition:
              'Active user-created races, excluding featured events and tournaments.',
          window: 'CURRENT SNAPSHOT',
        ),
        _MetricRow(
          label: 'Active daily races',
          value: _number(races?.integer('activeDailyRaces')),
          definition: 'Active races joined to a DAILY featured seed.',
          window: 'CURRENT SNAPSHOT',
        ),
        _MetricRow(
          label: 'Non-featured races created today',
          value: _number(races?.integer('nonFeaturedRacesCreatedToday')),
          definition: 'User-created races created in the current ET day.',
          window: 'TODAY · ET',
        ),
      ],
    );
  }

  Widget _growth(BuildContext context, AdminMetricMap? block) {
    if (block == null) {
      return const AdminMetricsStatePanel(message: _unavailable);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MetricRow(
          label: 'Observed foreground WAU',
          value: _number(block.integer('observedForegroundWau')),
          definition:
              'Distinct capable iOS foreground users over seven ET days.',
          coverage: envelope.coverage.metric('observedForegroundWau'),
          source: 'FOREGROUND TELEMETRY',
          window: 'TRAILING 7D · ET',
        ),
        _MetricRow(
          label: 'Observed foreground MAU',
          value: _number(block.integer('observedForegroundMau')),
          definition:
              'Distinct capable iOS foreground users over thirty ET days.',
          coverage: envelope.coverage.metric('observedForegroundMau'),
          source: 'FOREGROUND TELEMETRY',
          window: 'TRAILING 30D · ET',
        ),
        const _MetricHeading('DAILY'),
        for (final day in block.rows('daily')) ...[
          _MetricRow(
            label: '${day.text('date') ?? _unavailable} · signups',
            value: _number(day.integer('signups')),
            definition: 'New non-review iOS accounts created on this ET date.',
            window: '${day.text('date') ?? 'DATE UNAVAILABLE'} · ET DAY',
          ),
          _MetricRow(
            label: '${day.text('date') ?? _unavailable} · observed foreground',
            value: _number(day.integer('observedForegroundUsers')),
            definition:
                'Capable iOS users with a foreground fact on this ET date.',
            source: 'FOREGROUND TELEMETRY',
            window: '${day.text('date') ?? 'DATE UNAVAILABLE'} · ET DAY',
            coverage: envelope.coverage.metric('observedForegroundDau'),
            coverageLabel: _coverageDescription(
              envelope.coverage.metric('observedForegroundDau'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _invite(BuildContext context, AdminMetricMap? block) {
    if (block == null) {
      return const AdminMetricsStatePanel(message: _unavailable);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MetricRow(
          label: 'Referral link opens',
          value: _number(block.integer('linkOpens')),
          definition:
              'Link-open events during the selected window for iOS-owned referral codes.',
        ),
        _MetricRow(
          label: 'Unique referral link opens',
          value: _number(block.integer('uniqueLinkOpens')),
          definition:
              'Pseudonymously deduplicated link-open sessions during the same window.',
        ),
        _MetricRow(
          label: 'Attributed signups',
          value: _number(block.integer('attributedSignups')),
          definition:
              'iOS signup-cohort users attributed to an iOS-owned referral code.',
        ),
        _MetricRow(
          label: 'Joined race',
          value: _number(block.integer('joinedRace')),
          definition:
              'Attributed signup users reaching the canonical joined-race stage.',
        ),
        _MetricRow(
          label: 'Qualified / finished',
          value: _number(block.integer('qualified')),
          definition:
              'Attributed signup users reaching the canonical qualified stage.',
        ),
        _MetricRow(
          label: 'Rewarded',
          value: _number(block.integer('rewarded')),
          definition: 'Qualified referrals with a durable reward fact.',
        ),
        const _MetricHeading('CONVERSION'),
        _MetricRow(
          label: 'Unique open → signup',
          value: _ratio(block.ratio('openToSignup')),
          definition:
              'Attributed signups divided by unique referral link opens in one window.',
        ),
        _MetricRow(
          label: 'Signup → joined race',
          value: _ratio(block.ratio('signupToJoinedRace')),
          definition: 'Joined-race users divided by attributed signups.',
        ),
        _MetricRow(
          label: 'Joined → qualified',
          value: _ratio(block.ratio('joinedRaceToQualified')),
          definition: 'Qualified users divided by joined-race users.',
        ),
        _MetricRow(
          label: 'Qualified → rewarded',
          value: _ratio(block.ratio('qualifiedToRewarded')),
          definition: 'Rewarded users divided by qualified users.',
        ),
      ],
    );
  }

  Widget _onboarding(BuildContext context, AdminMetricMap? block) {
    if (block == null) {
      return const AdminMetricsStatePanel(message: _unavailable);
    }
    return OnboardingFunnelSection(dashboardFunnel: block);
  }

  Widget _activation(BuildContext context, AdminMetricMap? block) {
    if (block == null) {
      return const AdminMetricsStatePanel(message: _unavailable);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MetricRow(
          label: 'Health connected within 24h',
          value: _ratio(block.ratio('healthWithin24h')),
          definition:
              'Mature capable signup cohort with an iOS HealthKit connection event within 24 hours.',
          coverage: envelope.coverage.metric('healthWithin24h'),
          source: 'ACTIVATION TELEMETRY + PRODUCT DB',
          window: 'SIGNUP COHORT · FIRST 24 ELAPSED HOURS',
        ),
        _MetricRow(
          label: 'Joined / created race within 24h',
          value: _ratio(block.ratio('raceWithin24h')),
          definition:
              'Mature signups whose first eligible race join/create occurred within 24 elapsed hours.',
          window: 'SIGNUP COHORT · FIRST 24 ELAPSED HOURS',
        ),
        _MetricRow(
          label: 'Power used in first eligible race',
          value: _ratio(block.ratio('firstRacePowerUse')),
          definition:
              'Users using a powerup in their first eligible post-coverage race.',
          coverage: envelope.coverage.metric('firstRacePowerUse'),
        ),
        const _MetricHeading('DAILY RACE ACTIVATION'),
        for (final day in block.rows('daily')) ...[
          _MetricRow(
            label: '${day.text('date') ?? _unavailable} · live participants',
            value: _number(day.integer('liveRaceParticipants')),
            definition:
                'Distinct accepted users in eligible races overlapping this ET date.',
            window: '${day.text('date') ?? 'DATE UNAVAILABLE'} · ET DAY',
          ),
          _MetricRow(
            label: '${day.text('date') ?? _unavailable} · creators / races',
            value:
                '${_number(day.integer('raceCreators'))} / ${_number(day.integer('racesCreated'))}',
            definition:
                'Distinct race creators and eligible races created on this ET date.',
            window: '${day.text('date') ?? 'DATE UNAVAILABLE'} · ET DAY',
          ),
        ],
        const _MetricHeading('FRIENDS PER USER'),
        for (final row in block.rows('friends'))
          _MetricRow(
            label: '${row.text('bucket') ?? _unavailable} friends',
            value: _ratio(row.ratio('ratio')),
            definition:
                'Accepted-friend count bucket across retained non-review iOS accounts.',
            window: 'CURRENT RETAINED-ACCOUNT SNAPSHOT',
          ),
      ],
    );
  }

  Widget _retention(BuildContext context, AdminMetricMap? block) {
    if (block == null) {
      return const AdminMetricsStatePanel(message: _unavailable);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final horizon in const [
          ('d1', 'D1', 'retentionD1'),
          ('d7', 'D7', 'retentionD7'),
          ('d30', 'D30', 'retentionD30'),
        ])
          _MetricRow(
            label: 'Observed ${horizon.$2}',
            value: _ratio(block.ratio(horizon.$1)),
            definition:
                'Exact-day foreground return in the immutable signup-capable cohort.',
            coverage: envelope.coverage.metric(horizon.$3),
            source: 'FOREGROUND TELEMETRY + PRODUCT DB',
            window: 'SIGNUP COHORT · EXACT ${horizon.$2} ET DAY',
          ),
        _MetricRow(
          label: 'Completed first race → another within 7d',
          value: _ratio(block.ratio('secondRaceWithin7d')),
          definition:
              'Eligible finishers joining a different race after completion within seven elapsed days.',
          window: 'FIRST FINISH · NEXT 7 ELAPSED DAYS',
        ),
        _MetricRow(
          label: 'Completed first race → another within 30d',
          value: _ratio(block.ratio('secondRaceWithin30d')),
          definition:
              'Eligible finishers joining a different race after completion within thirty elapsed days.',
          window: 'FIRST FINISH · NEXT 30 ELAPSED DAYS',
        ),
        if (block.rows('cohorts').isNotEmpty)
          const _MetricHeading('SIGNUP COHORTS'),
        for (final cohort in block.rows('cohorts'))
          _MetricRow(
            label: cohort.text('signupDate') ?? _unavailable,
            value:
                'eligible ${_number(cohort.integer('eligibleSignups'))} · D1 ${_ratio(cohort.ratio('d1'))} · D7 ${_ratio(cohort.ratio('d7'))} · D30 ${_ratio(cohort.ratio('d30'))}',
            definition:
                'One ET signup-date cohort; immature horizon leaves stay unavailable.',
            source: 'FOREGROUND TELEMETRY + PRODUCT DB',
            window:
                '${cohort.text('signupDate') ?? 'DATE UNAVAILABLE'} COHORT · D1/D7/D30',
            coverageLabel: _retentionCoverage(envelope),
          ),
      ],
    );
  }

  Widget _engagement(BuildContext context, AdminMetricMap? block) {
    if (block == null) {
      return const AdminMetricsStatePanel(message: _unavailable);
    }
    final balance = block.map('coinBalance');
    final featured = block.map('featuredParticipation');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MetricRow(
          label: 'Average runners / started race',
          value: _decimal(block.decimal('averageRunnersPerStartedRace')),
          definition:
              'Mean accepted participants for non-cancelled races started in the selected window.',
        ),
        _MetricRow(
          label: 'Public races',
          value: _ratio(
            block.map('visibility')?.ratio('public') ?? const AdminRatio(),
          ),
          definition:
              'Eligible races created in-window where is_public is true.',
        ),
        _MetricRow(
          label: 'Private races',
          value: _ratio(
            block.map('visibility')?.ratio('private') ?? const AdminRatio(),
          ),
          definition:
              'Eligible races created in-window where is_public is false.',
        ),
        _MetricRow(
          label: 'Races / observed active user',
          value: _average(block.average('racesPerObservedActiveUser')),
          definition:
              'Eligible live-race memberships held by observed foreground users; zero-race users remain in denominator.',
          coverage: envelope.coverage.metric('observedForegroundDau'),
          source: 'FOREGROUND TELEMETRY + PRODUCT DB',
        ),
        _MetricRow(
          label: 'Leaderboard views / capable racer',
          value: _average(block.average('leaderboardViewsPerCapableRacer')),
          definition:
              'Intentional leaderboard views divided by telemetry-capable accepted racers.',
          coverage: envelope.coverage.metric('leaderboardViews'),
          source: 'ACTIVATION TELEMETRY + PRODUCT DB',
        ),
        _MetricRow(
          label: 'Powerups / race',
          value: _average(block.average('powerupsPerRace')),
          definition:
              'Durable POWERUP_USED events divided by eligible powerups-enabled races.',
        ),
        const _MetricHeading('COIN BALANCE · CURRENT SNAPSHOT'),
        _MetricRow(
          label: 'Accounts / total',
          value:
              '${_number(balance?.integer('populationCount'))} / ${_number(balance?.integer('total'))}',
          definition:
              'Current coin balance across retained non-review iOS accounts.',
          window: 'CURRENT SNAPSHOT',
        ),
        _MetricRow(
          label: 'Mean / median / p90',
          value:
              '${_decimal(balance?.decimal('average'))} / ${_decimal(balance?.decimal('median'))} / ${_decimal(balance?.decimal('p90'))}',
          definition:
              'Current distribution snapshot; median is shown beside mean to expose skew.',
          window: 'CURRENT SNAPSHOT',
        ),
        const _MetricHeading('FEATURED + RANKED'),
        for (final cadence in const [('daily', 'Daily'), ('weekly', 'Weekly')])
          _MetricRow(
            label: '${cadence.$2} users / memberships',
            value:
                '${_number(featured?.map(cadence.$1)?.integer('activeOverlapUsers'))} / ${_number(featured?.map(cadence.$1)?.integer('activeOverlapMemberships'))} live · ${_number(featured?.map(cadence.$1)?.integer('joinedWindowUsers'))} / ${_number(featured?.map(cadence.$1)?.integer('joinedWindowMemberships'))} joined',
            definition:
                'Accepted users and memberships for non-cancelled featured races.',
          ),
        _MetricRow(
          label: 'Ranked participation users',
          value: _number(block.integer('rankedParticipationUsers')),
          definition:
              'Distinct users assigned to Ranked v2 cohorts overlapping the window.',
        ),
        _MetricRow(
          label: 'Notification open rate · 7d',
          value: _ratio(block.ratio('notificationOpenRate')),
          definition:
              'Distinct opened provider-accepted visible APNs sends; not device-delivery rate.',
          coverage: envelope.coverage.metric('notificationOpen'),
          source: 'NOTIFICATION RECEIPTS + PRODUCT DB',
          window: 'TRAILING 7D · ET',
        ),
        for (final row
            in block.map('notificationOpenRate')?.rows('breakdown') ??
                const <AdminMetricMap>[])
          _MetricRow(
            label: 'Push · ${row.text('notificationType') ?? _unavailable}',
            value: _ratio(row.ratio('ratio')),
            definition:
                'Provider-accepted APNs opens for this notification type.',
            source: 'NOTIFICATION RECEIPTS + PRODUCT DB',
            window: 'TRAILING 7D · ET',
            coverage: envelope.coverage.metric('notificationOpen'),
            coverageLabel: _coverageDescription(
              envelope.coverage.metric('notificationOpen'),
            ),
          ),
        const _MetricHeading('DAILY · RETAINED-ACCOUNT HISTORY'),
        for (final day in block.rows('daily')) ...[
          _MetricRow(
            label:
                '${day.text('date') ?? _unavailable} · races created / started',
            value:
                '${_number(day.integer('racesCreated'))} / ${_number(day.integer('racesStarted'))}',
            definition:
                'Eligible user-created races by ET created and started dates.',
            window: '${day.text('date') ?? 'DATE UNAVAILABLE'} · ET DAY',
          ),
          _MetricRow(
            label:
                '${day.text('date') ?? _unavailable} · new / live participants',
            value:
                '${_number(day.integer('newParticipants'))} / ${_number(day.integer('liveRaceParticipants'))}',
            definition:
                'Accepted joins on this date versus users in races overlapping this date.',
            window: '${day.text('date') ?? 'DATE UNAVAILABLE'} · ET DAY',
          ),
          _MetricRow(
            label: '${day.text('date') ?? _unavailable} · powerups used',
            value: _number(day.integer('powerupsUsed')),
            definition: 'Durable POWERUP_USED server events on this ET date.',
            window: '${day.text('date') ?? 'DATE UNAVAILABLE'} · ET DAY',
          ),
          _MetricRow(
            label:
                '${day.text('date') ?? _unavailable} · gross credits / debits',
            value:
                '${_number(day.integer('grossCoinCredits'))} / ${_number(day.integer('grossCoinDebits'))}',
            definition:
                'Positive and absolute negative ledger movement for retained accounts; not minted/sunk.',
            window: '${day.text('date') ?? 'DATE UNAVAILABLE'} · ET DAY',
          ),
          _MetricRow(
            label:
                '${day.text('date') ?? _unavailable} · reward claims / claimers',
            value:
                '${_number(day.integer('dailyRewardClaims'))} / ${_number(day.integer('distinctDailyRewardClaimers'))}',
            definition:
                'Retained-account daily reward claims and distinct claimers.',
            window: '${day.text('date') ?? 'DATE UNAVAILABLE'} · ET DAY',
          ),
        ],
      ],
    );
  }

  Widget _virality(BuildContext context, AdminMetricMap? block) {
    if (block == null) {
      return const AdminMetricsStatePanel(message: _unavailable);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MetricRow(
          label: 'Attributed signups',
          value: _number(block.integer('attributedSignups')),
          definition:
              'Selected-window iOS signups attributed to iOS-owned referral codes.',
        ),
        _MetricRow(
          label: 'Attributed signups / observed WAU',
          value: _decimal(block.decimal('attributedSignupsPerWau')),
          definition:
              'Attributed signups divided by capability-scoped observed WAU; this is not K-factor.',
          coverage: envelope.coverage.metric('observedForegroundWau'),
          source: 'FOREGROUND TELEMETRY + PRODUCT DB',
          window: 'SELECTED ATTRIBUTION WINDOW / TRAILING 7D OBSERVED WAU',
        ),
        _MetricRow(
          label: 'Unique link open → signup',
          value: _ratio(block.ratio('linkOpenToSignup')),
          definition:
              'Attributed signups divided by pseudonymously deduped link-open sessions.',
        ),
      ],
    );
  }

  Widget _revenue(BuildContext context, AdminMetricMap? block) {
    if (block == null) {
      return const AdminMetricsStatePanel(message: _unavailable);
    }
    final daily = block.rows('daily');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Signed callbacks prove a rewarded interaction, but the recorded reward kind is not independently authenticated. Trends are retained-account history and can revise after account deletion.',
          style: PixelText.body(size: 11, color: AppColors.of(context).textMid),
        ),
        const SizedBox(height: 6),
        if (daily.isNotEmpty) const _MetricHeading('SIGNED REWARDED ADS'),
        for (final day in daily) ...[
          _MetricRow(
            label:
                '${day.text('date') ?? _unavailable} · Signed rewarded grants',
            value: _number(day.integer('ssvGrants')),
            definition:
                'Retained-account signed server-side reward callbacks on this callback ET date.',
            window: '${day.text('date') ?? 'DATE UNAVAILABLE'} · ET DAY',
          ),
          _MetricRow(
            label:
                '${day.text('date') ?? _unavailable} · Unique rewarded watchers',
            value: _number(day.integer('uniqueSsvWatchers')),
            definition:
                'Distinct retained iOS accounts with a signed callback on this date.',
            window: '${day.text('date') ?? 'DATE UNAVAILABLE'} · ET DAY',
          ),
          for (final reward in day.rows('ssvByRewardKind'))
            _MetricRow(
              label:
                  '${reward.text('rewardKind') ?? _unavailable} · grants / watchers',
              value:
                  '${_number(reward.integer('grants'))} / ${_number(reward.integer('uniqueWatchers'))}',
              definition:
                  'Signed callback totals grouped by the recorded reward kind.',
              window: '${day.text('date') ?? 'DATE UNAVAILABLE'} · ET DAY',
            ),
        ],
      ],
    );
  }

  Widget _release(BuildContext context, AdminMetricMap? block) {
    if (block == null) {
      return const AdminMetricsStatePanel(message: _unavailable);
    }
    final rawVersions = block.raw('versions');
    if (rawVersions is! List) {
      return const AdminMetricsStatePanel(message: _unavailable);
    }
    final versions = block.rows('versions');
    if (rawVersions.isNotEmpty && versions.isEmpty) {
      return const AdminMetricsStatePanel(message: _unavailable);
    }
    final windowDays = block.integer('windowDays');
    final releaseWindow = windowDays == null
        ? 'WINDOW UNAVAILABLE'
        : 'TRAILING ${windowDays}D · ET';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          windowDays == null
              ? 'Accounts seen by backend · window unavailable'
              : 'Accounts seen by backend in last ${windowDays}d',
          style: PixelText.body(size: 11, color: AppColors.of(context).textMid),
        ),
        const SizedBox(height: 6),
        if (versions.isEmpty)
          _MetricRow(
            label: 'Versions',
            value: '0',
            definition: 'No qualifying iOS accounts were seen in the window.',
            window: releaseWindow,
          )
        else
          for (final version in versions)
            _MetricRow(
              label: version.text('version') ?? _unavailable,
              value: _number(version.integer('accountsSeen')),
              definition:
                  'Non-review iOS accounts seen by the backend in the release-adoption window; not install base.',
              window: releaseWindow,
            ),
      ],
    );
  }
}

class AdminLegacyReleaseAdoptionBody extends StatelessWidget {
  const AdminLegacyReleaseAdoptionBody({super.key, required this.stats});

  final Map<String, dynamic>? stats;

  @override
  Widget build(BuildContext context) {
    final raw = stats?['versions'];
    final versionsSince = stats?['versionsSince'];
    final rows = <AdminMetricMap>[];
    if (raw is List) {
      for (final item in raw) {
        if (AdminMetricMap.from(item) case final parsed?) rows.add(parsed);
      }
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Accounts seen by backend in last 30d',
          style: PixelText.body(size: 11, color: AppColors.of(context).textMid),
        ),
        if (versionsSince is String)
          _MetricRow(
            label: 'Seen since',
            value: versionsSince,
            definition: 'Beginning of the legacy backend-seen version window.',
          ),
        for (final row in rows)
          _MetricRow(
            label:
                '${row.text('version') ?? 'unknown'}${row.text('platform') == null ? '' : ' (${row.text('platform')})'}',
            value: _number(row.integer('users')),
            definition: 'Legacy account version observation; not install base.',
          ),
      ],
    );
  }
}

class _MetadataStrip extends StatelessWidget {
  const _MetadataStrip({required this.envelope});

  final AdminMetricsEnvelope envelope;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final window = envelope.window;
    final productSource = envelope.sources.productDb;
    final foregroundSource = envelope.sources.foregroundActivity;
    final productStateLabel = switch (productSource.status) {
      AdminSourceStatus.available => null,
      AdminSourceStatus.stale => 'STALE',
      AdminSourceStatus.collecting => 'COLLECTING',
      _ => 'SOURCE UNAVAILABLE',
    };
    final foregroundLabel = switch (foregroundSource.status) {
      AdminSourceStatus.available => 'FOREGROUND · AVAILABLE',
      AdminSourceStatus.collecting => 'FOREGROUND · COLLECTING',
      AdminSourceStatus.stale => 'FOREGROUND · STALE',
      AdminSourceStatus.disabled => 'FOREGROUND · DISABLED',
      _ => 'FOREGROUND · UNAVAILABLE',
    };
    return Wrap(
      spacing: 6,
      runSpacing: 5,
      children: [
        _Badge('${window.days?.toString() ?? '?'}D'),
        _Badge(
          window.timeZone == 'America/New_York' ? 'ET' : 'TIMEZONE UNAVAILABLE',
        ),
        const _Badge('PRODUCT DB'),
        if (productStateLabel != null) _Badge(productStateLabel),
        _Badge(foregroundLabel),
        if (productSource.asOf != null) _Badge('AS OF ${productSource.asOf}'),
        if (window.start != null && window.end != null)
          Text(
            '${window.start} → ${window.end}',
            style: PixelText.body(size: 10, color: colors.textMid),
          ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: colors.parchmentDark.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.parchmentBorder, width: 1),
      ),
      child: Text(
        label,
        style: PixelText.title(size: 9, color: colors.textMid),
      ),
    );
  }
}

class _MetricHeading extends StatelessWidget {
  const _MetricHeading(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 4),
    child: Text(
      label,
      style: PixelText.title(size: 12, color: AppColors.of(context).textDark),
    ),
  );
}

class _MetricProvenanceScope extends InheritedWidget {
  const _MetricProvenanceScope({required this.envelope, required super.child});

  final AdminMetricsEnvelope envelope;

  static AdminMetricsEnvelope? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_MetricProvenanceScope>()
      ?.envelope;

  @override
  bool updateShouldNotify(_MetricProvenanceScope oldWidget) =>
      !identical(envelope, oldWidget.envelope);
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.label,
    required this.value,
    required this.definition,
    this.coverage,
    this.source = 'PRODUCT DB',
    this.window,
    this.coverageLabel,
  });

  final String label;
  final String value;
  final String definition;
  final AdminMetricCoverage? coverage;
  final String source;
  final String? window;
  final String? coverageLabel;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final coverageText =
        coverageLabel ??
        (coverage == null ? null : _coverageDescription(coverage));
    final envelope = _MetricProvenanceScope.maybeOf(context);
    final days = envelope?.window.days;
    final timezone = envelope?.window.timeZone;
    final selectedWindow = days == null
        ? 'SELECTED WINDOW UNAVAILABLE'
        : 'SELECTED ${days}D · ${timezone == 'America/New_York' ? 'ET' : timezone ?? 'TIMEZONE UNAVAILABLE'}';
    final windowText = window ?? selectedWindow;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: PixelText.body(size: 12, color: colors.textMid),
                ),
                if (coverageText != null)
                  Text(
                    coverageText,
                    style: PixelText.title(size: 9, color: colors.textAccent),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 4,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: PixelText.title(size: 12, color: colors.textDark),
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
                          definition,
                          style: PixelText.body(
                            size: 13,
                            color: AppColors.of(sheetContext).textMid,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'SOURCE · $source',
                          style: PixelText.title(
                            size: 10,
                            color: AppColors.of(sheetContext).textAccent,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'WINDOW · $windowText',
                          style: PixelText.title(
                            size: 10,
                            color: AppColors.of(sheetContext).textAccent,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'COVERAGE · ${coverageText ?? 'NOT APPLICABLE'}',
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
